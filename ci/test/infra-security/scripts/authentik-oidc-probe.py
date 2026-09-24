"""Drives authentik as an OIDC provider the way this estate's clients use it.

Runs INSIDE the authentik-oidc-setup and authentik-oidc-login Job pods (stdlib Python only),
never on the chainsaw runner. validate-authentik-oidc.yaml mounts it from a ConfigMap and
binds every expected value into the environment from live cluster state.

  setup  the administrator's side: wait for authentik's default blueprints, then create
         the client over the REST API in the shape every OIDC client in the estate shares
  login  the browser's side: sign in through a real relying party (oidc-test-client),
         then check what it received against the cert-manager signing certificate

One line per leg, `OIDC OK   [<leg>] ...` or `OIDC FAIL [<leg>] ...`; exit 1 on the first
failure.
"""

import base64
import hashlib
import http.client
import json
import os
import re
import ssl
import sys
import time
import urllib.parse

T0 = time.time()
ENV = os.environ
REAPPLY_LIMIT = 3
REAPPLY_EVERY_S = 15


def ok(leg, msg):
    print(f"OIDC OK   [{leg}] {msg} (t+{int(time.time() - T0)}s)", flush=True)


def fail(leg, msg):
    print(f"OIDC FAIL [{leg}] {msg} (t+{int(time.time() - T0)}s)", flush=True)
    sys.exit(1)


# The issuer origin is the Ingress host consumers configure. The pod resolves it straight to
# the authentik-server Service (hostAliases), so requests arrive over authentik's own TLS
# listener carrying the real Host -- no Traefik in between, and no forged forwarding headers.
ISSUER_HOST = ENV["ISSUER_HOST"]
ORIGIN = f"https://{ISSUER_HOST}"
# authentik's listener serves its own self-signed certificate; in the estate clients see
# Traefik's. Neither is what this probe is about.
TLS = ssl._create_unverified_context()


class Browser:
    """A cookie jar and a request function. authentik scopes its cookies to the cookie domain
    (the parent zone), which http.cookiejar would drop for these hosts, so cookies are kept
    per host by hand: a relying party's session must not leak into authentik's or back."""

    def __init__(self):
        self.jars = {}

    def request(self, method, url, body=None, form=False, headers=None):
        u = urllib.parse.urlsplit(url)
        jar = self.jars.setdefault(u.netloc, {})
        h = {"Accept": "application/json"}
        if jar:
            h["Cookie"] = "; ".join(f"{k}={v}" for k, v in jar.items())
        data = None
        if body is not None:
            if form:
                data = urllib.parse.urlencode(body).encode()
                h["Content-Type"] = "application/x-www-form-urlencoded"
            else:
                data = json.dumps(body).encode()
                h["Content-Type"] = "application/json"
        # Django's CSRF check for a session-authenticated API call: token cookie echoed in
        # the header, and an Origin matching the Host.
        if method != "GET" and "authentik_csrf" in jar:
            h["X-authentik-CSRF"] = jar["authentik_csrf"]
            h["Origin"] = f"{u.scheme}://{u.netloc}"
            h["Referer"] = f"{u.scheme}://{u.netloc}/"
        h.update(headers or {})
        if u.scheme == "https":
            conn = http.client.HTTPSConnection(u.hostname, u.port or 443, timeout=20, context=TLS)
        else:
            conn = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=20)
        path = u.path + (f"?{u.query}" if u.query else "")
        conn.request(method, path or "/", body=data, headers=h)
        resp = conn.getresponse()
        raw = resp.read()
        for k, v in resp.getheaders():
            if k.lower() == "set-cookie":
                name, _, rest = v.partition("=")
                jar[name.strip()] = rest.split(";", 1)[0]
        conn.close()
        loc = resp.getheader("Location")
        if loc:
            loc = urllib.parse.urljoin(url, loc)
        return resp.status, loc, raw


def as_json(leg, status, raw, want=(200,)):
    if status not in want:
        fail(leg, f"HTTP {status}: {raw[:300]!r}")
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except ValueError:
        fail(leg, f"HTTP {status}, not JSON: {raw[:300]!r}")


def run_flow(b, leg, flow_url, answer):
    """Walk an authentik flow through its executor API, the way the flow interface does, and
    return where the flow redirects to. `answer(challenge)` builds each response body."""
    u = urllib.parse.urlsplit(flow_url)
    slug = u.path.rstrip("/").rsplit("/", 1)[-1]
    api = f"{ORIGIN}/api/v3/flows/executor/{slug}/?query={urllib.parse.quote(u.query)}"
    status, _, raw = b.request("GET", api)
    seen = []
    for _ in range(12):
        # The executor answers "fetch me again" with a bare 302 to its own URL, e.g. once a
        # stage has rotated the session.
        if status == 302:
            status, _, raw = b.request("GET", api)
            continue
        ch = as_json(leg, status, raw)
        comp = ch.get("component")
        seen.append(comp)
        if comp == "xak-flow-redirect":
            return ch["to"], seen
        if ch.get("response_errors"):
            fail(leg, f"{slug}: {comp} rejected the answer: {json.dumps(ch['response_errors'])}")
        body = answer(ch)
        if body is None:
            return ch, seen
        status, _, raw = b.request("POST", api, body)
    fail(leg, f"{slug}: no redirect after challenges {seen}")


def follow(b, leg, url, until, answer):
    """Follow redirects the way a browser would, running any authentik flow met on the way.
    Returns ("arrived", url) at the first URL starting with `until`, ("challenge", ch) for a
    flow challenge `answer` declined, or ("page", (status, url, body)) for a response that
    is neither a redirect nor a flow."""
    for _ in range(12):
        if url.startswith(until):
            return "arrived", url
        if urllib.parse.urlsplit(url).path.startswith("/if/flow/"):
            to, _ = run_flow(b, leg, url, answer)
            if isinstance(to, dict):
                return "challenge", to
            url = urllib.parse.urljoin(url, to)
            continue
        status, loc, raw = b.request("GET", url)
        if status not in (301, 302, 303, 307) or not loc:
            return "page", (status, url, raw)
        url = loc
    fail(leg, f"no arrival at {until} after 12 hops")


def arrive(b, leg, url, until, answer):
    kind, got = follow(b, leg, url, until, answer)
    if kind != "arrived":
        fail(leg, f"stopped before {until}: {kind} {str(got)[:300]}")
    return got


def sign_in(username, password):
    def answer(ch):
        comp = ch["component"]
        if comp == "ak-stage-identification":
            return {"component": comp, "uid_field": username}
        if comp == "ak-stage-password":
            return {"component": comp, "password": password}
        if comp == "ak-stage-consent":
            return {"component": comp, "token": ch["token"]}
        return None

    return answer


# ---------------------------------------------------------------------------- setup


def setup():
    # The admin credential is authentik's bootstrap token, set for this suite only through
    # the Flux Kustomization's patches (infra-security-extra.yaml). authentik applies it
    # synchronously at server start, so it is usable as soon as the API answers.
    api = Browser()
    auth = {"Authorization": f"Bearer {ENV['ADMIN_TOKEN']}"}

    def get(path):
        status, _, raw = api.request("GET", f"{ORIGIN}/api/v3/{path}", headers=auth)
        return status, raw

    def call(leg, method, path, body=None, want=(200,)):
        status, _, raw = api.request(method, f"{ORIGIN}/api/v3/{path}", body, headers=auth)
        return as_json(leg, status, raw, want)

    # Nothing below may start before the worker has applied every default blueprint: they
    # create the flows, stages and scope mappings the client and the sign-in use, in no
    # fixed order, and a Ready worker is still applying them. Sampling objects that happen to
    # be missing caught one run per symptom; this waits on what completion must leave
    # behind. Discovery creates an instance per blueprint file lazily (status "unknown"),
    # so every instance being "successful" is not enough on its own: every instantiable
    # file in `available` must have an enabled instance, successful, whose last applied hash
    # is that file's hash.
    #
    # On a fresh install the worker can apply one blueprint twice at once, and the loser
    # ends in "error" with a Postgres "deadlock detected" (seen on the rig, on
    # default/flow-oobe.yaml, whose first apply had succeeded 8s earlier); nothing re-applies
    # it until the hourly discovery. So an errored blueprint is re-applied through the API,
    # as an administrator would, up to REAPPLY_LIMIT times; one that keeps failing is a
    # blueprint that cannot apply, and fails the leg without waiting out the budget.
    by = time.time() + int(ENV["BLUEPRINT_BUDGET_S"])
    reapplied = {}
    # The file list is fixed by the image, and each `available` call is a task queued on
    # the worker behind the very applies being waited for, so it is read once.
    files, s1 = None, None
    while files is None:
        s1, raw1 = get("managed/blueprints/available/")
        if s1 == 200:
            files = [f for f in json.loads(raw1)
                     if ((f.get("meta") or {}).get("labels") or {}).get(
                         "blueprints.goauthentik.io/instantiate", "").lower() != "false"]
        elif time.time() > by:
            fail("blueprints", f"blueprint file list: API HTTP {s1}")
        else:
            time.sleep(3)
    while True:
        pending = None
        s2, raw2 = get("managed/blueprints/?page_size=1000")
        if s2 == 200:
            inst = {i["path"]: i for i in json.loads(raw2)["results"]}
            pending = []
            for f in files:
                i = inst.get(f["path"])
                if i is None:
                    pending.append(f"{f['path']}: no instance")
                    continue
                if not i["enabled"] or (i["status"] == "successful" and i["last_applied_hash"] == f["hash"]):
                    continue
                pending.append(f"{f['path']}: {i['status']}")
                if i["status"] != "error":
                    continue
                n, at = reapplied.get(f["path"], (0, 0))
                if time.time() - at < REAPPLY_EVERY_S:
                    continue
                if n >= REAPPLY_LIMIT:
                    fail("blueprints", f"{f['path']} still in error after {n} re-applies")
                call("blueprints", "POST", f"managed/blueprints/{i['pk']}/apply/")
                reapplied[f["path"]] = (n + 1, time.time())
            if files and not pending:
                break
        if time.time() > by:
            fail("blueprints", f"default blueprints not all applied: "
                               f"{pending if pending is not None else f'API HTTP {s2}'}")
        time.sleep(3)
    again = ", ".join(f"{p} x{n}" for p, (n, _) in reapplied.items()) or "none"
    ok("blueprints", f"all {len(files)} default blueprints applied at their current file hash "
                     f"(re-applied after error: {again})")

    # The Terraform workspace looks the signing key up by the name the module's mount gives
    # it, so the discovered pair must exist under that name AND be the cert-manager certificate.
    want_fp = hashlib.sha256(pem_to_der(ENV["SIGNING_CERT_PEM"])).hexdigest()
    budget = time.time() + int(ENV["DISCOVERY_BUDGET_S"])
    while True:
        found = call("signing-key", "GET", "crypto/certificatekeypairs/?name=jwt-signing")["results"]
        if found and found[0].get("private_key_available"):
            break
        if time.time() > budget:
            fail("signing-key", f"no certificate-key pair 'jwt-signing' with a private key: {found}")
        time.sleep(5)
    kp = found[0]
    got_fp = kp["fingerprint_sha256"].replace(":", "").lower()
    if got_fp != want_fp:
        fail("signing-key", f"'jwt-signing' is {got_fp}, the cert-manager certificate is {want_fp}")
    ok("signing-key", f"'jwt-signing' discovered with its private key, sha256 {want_fp[:16]}...")

    def one(leg, path):
        res = call(leg, "GET", path)["results"]
        if len(res) != 1:
            fail(leg, f"{path}: expected one match, got {len(res)}")
        return res[0]

    authz = one("client", "flows/instances/?slug=default-provider-authorization-implicit-consent")
    inval = one("client", "flows/instances/?slug=default-provider-invalidation-flow")
    scopes = sorted(
        one("client", f"propertymappings/provider/scope/?managed=goauthentik.io/providers/oauth2/scope-{s}")["pk"]
        for s in ("email", "openid", "profile", "offline_access")
    )

    group = call("client", "POST", "core/groups/", {"name": ENV["GROUP"]}, (201,))
    for username, member in ((ENV["MEMBER_USERNAME"], True), (ENV["OUTSIDER_USERNAME"], False)):
        user = call("client", "POST", "core/users/", {
            "username": username,
            "name": username,
            "email": f"{username}@{ENV['EMAIL_DOMAIN']}",
            "groups": [group["pk"]] if member else [],
        }, (201,))
        call("client", "POST", f"core/users/{user['pk']}/set_password/",
             {"password": ENV["USER_PASSWORD"]}, (204,))

    # The Terraform module's shape, validities included (its defaults). It does not set
    # grant_types, which authentik added later and backfilled with every grant type on
    # existing providers; these two are the ones the estate's clients use.
    slug = ENV["APP_SLUG"]
    provider = call("client", "POST", "providers/oauth2/", {
        "name": f"{slug}-oidc",
        "client_type": "confidential",
        "client_id": ENV["CLIENT_ID"],
        "client_secret": ENV["CLIENT_SECRET"],
        "grant_types": ["authorization_code", "refresh_token"],
        "redirect_uris": [{"matching_mode": "strict", "url": ENV["REDIRECT_URI"]}],
        "include_claims_in_id_token": True,
        "signing_key": kp["pk"],
        "property_mappings": scopes,
        "authorization_flow": authz["pk"],
        "invalidation_flow": inval["pk"],
        "access_code_validity": "minutes=1",
        "access_token_validity": "hours=1",
        "refresh_token_validity": "hours=4",
    }, (201,))
    app = call("client", "POST", "core/applications/", {
        "name": slug, "slug": slug, "provider": provider["pk"], "open_in_new_tab": True,
    }, (201,))
    call("client", "POST", "policies/bindings/",
         {"group": group["pk"], "target": app["pk"], "order": 0}, (201,))
    ok("client", f"provider {slug}-oidc + application {slug}, bound to group {ENV['GROUP']}")


# ---------------------------------------------------------------------------- login


def b64url(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def pem_to_der(b64pem):
    pem = base64.b64decode(b64pem).decode()
    body = re.search(r"-----BEGIN CERTIFICATE-----(.+?)-----END CERTIFICATE-----", pem, re.S)
    return base64.b64decode("".join(body.group(1).split()))


def der_walk(der, i):
    """(tag, content_start, content_end) of the DER element at i."""
    tag, ln = der[i], der[i + 1]
    i += 2
    if ln & 0x80:
        n = ln & 0x7F
        ln = int.from_bytes(der[i:i + n], "big")
        i += n
    return tag, i, i + ln


def rsa_key_of(der):
    """(n, e) of an X.509 certificate's RSA public key."""
    _, i, _ = der_walk(der, 0)                    # Certificate
    _, i, _ = der_walk(der, i)                    # tbsCertificate
    if der[i] == 0xA0:                            # [0] version
        i = der_walk(der, i)[2]
    for _ in range(5):                            # serial, signature, issuer, validity, subject
        i = der_walk(der, i)[2]
    _, i, _ = der_walk(der, i)                    # subjectPublicKeyInfo
    i = der_walk(der, i)[2]                       # algorithm
    _, i, _ = der_walk(der, i)                    # BIT STRING
    _, i, _ = der_walk(der, i + 1)                # RSAPublicKey (after the unused-bits byte)
    _, s, e_ = der_walk(der, i)
    n = int.from_bytes(der[s:e_], "big")
    _, s, e2 = der_walk(der, e_)
    return n, int.from_bytes(der[s:e2], "big")


SHA256_PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")


def rs256_valid(token, n, e):
    """RSASSA-PKCS1-v1_5 / SHA-256, as RFC 8017 8.2.2 specifies it."""
    head, payload, sig = token.split(".")
    k = (n.bit_length() + 7) // 8
    s = b64url(sig)
    if len(s) != k:
        return False
    em = pow(int.from_bytes(s, "big"), e, n).to_bytes(k, "big")
    t = SHA256_PREFIX + hashlib.sha256(f"{head}.{payload}".encode()).digest()
    return em == b"\x00\x01" + b"\xff" * (k - len(t) - 3) + b"\x00" + t


def login():
    issuer = f"{ORIGIN}/application/o/{ENV['APP_SLUG']}/"
    rp = ENV["RP_URL"].rstrip("/")
    member, outsider = ENV["MEMBER_USERNAME"], ENV["OUTSIDER_USERNAME"]

    # A user who is in the bound group signs in through the relying party. oidc-test-client
    # (go-oidc) exchanges the code, verifies the ID token against the advertised JWKS
    # (issuer, audience, expiry, signature), calls userinfo and refreshes; it answers the
    # callback with what it got, or redirects back to its start page on any failure.
    b = Browser()
    cb = arrive(b, "sign-in", f"{rp}/", f"{rp}/auth/callback", sign_in(member, ENV["USER_PASSWORD"]))
    status, loc, raw = b.request("GET", cb)
    if status != 200:
        fail("relying-party", f"oidc-test-client rejected the callback (HTTP {status} -> {loc}); "
                              "its log says why")
    got = json.loads(raw)
    missing = [k for k in ("RawIDToken", "UserInfo", "Refresh", "RefreshIDToken") if not got.get(k)]
    if missing:
        fail("relying-party", f"oidc-test-client response lacks {missing}")
    ok("relying-party", "go-oidc verified the ID token, fetched userinfo and refreshed "
                        f"({member} via {rp})")

    # go-oidc accepts a signature by ANY key in the JWKS. The estate's clients rely on
    # something narrower: the key is the cert-manager certificate from certificate-signing.yaml.
    cert_der = pem_to_der(ENV["SIGNING_CERT_PEM"])
    want_n, want_e = rsa_key_of(cert_der)
    tok = got["RawIDToken"]
    header = json.loads(b64url(tok.split(".")[0]))
    if header.get("alg") != "RS256":
        fail("signature", f"ID token alg is {header.get('alg')}, want RS256")
    status, _, raw = b.request("GET", f"{issuer}jwks/")
    keys = [k for k in as_json("signature", status, raw).get("keys", []) if k.get("kid") == header.get("kid")]
    if len(keys) != 1:
        fail("signature", f"JWKS has {len(keys)} keys with kid {header.get('kid')}")
    jwk = keys[0]
    if (int.from_bytes(b64url(jwk["n"]), "big"), int.from_bytes(b64url(jwk["e"]), "big")) != (want_n, want_e):
        fail("signature", "JWKS key for the token's kid is not the cert-manager certificate's key")
    if base64.b64decode(jwk.get("x5c", [""])[0]) != cert_der:
        fail("signature", "JWKS x5c is not the cert-manager certificate")
    if not rs256_valid(tok, want_n, want_e):
        fail("signature", "ID token signature does not verify under the cert-manager key")
    # The verifier's own negative control: it must reject one flipped bit.
    h, p, s = tok.split(".")
    flipped = bytearray(b64url(s))
    flipped[-1] ^= 1
    if rs256_valid(f"{h}.{p}.{base64.urlsafe_b64encode(bytes(flipped)).decode().rstrip('=')}", want_n, want_e):
        fail("signature", "verifier accepted a tampered signature")
    ok("signature", f"RS256 by the cert-manager key (kid {header['kid'][:12]}...), tampered copy rejected")

    claims = json.loads(b64url(tok.split(".")[1]))
    email = f"{member}@{ENV['EMAIL_DOMAIN']}"
    for where, c in (("id_token", claims), ("userinfo", got["UserInfo"])):
        want = {"email": email, "preferred_username": member}
        if where == "id_token":
            want.update(iss=issuer)
        bad = {k: c.get(k) for k, v in want.items() if c.get(k) != v}
        if bad:
            fail("claims", f"{where}: {bad}, want {want}")
        if ENV["GROUP"] not in (c.get("groups") or []):
            fail("claims", f"{where}: groups {c.get('groups')} lacks {ENV['GROUP']}")
    aud = claims.get("aud")
    if aud != ENV["CLIENT_ID"] and ENV["CLIENT_ID"] not in (aud if isinstance(aud, list) else []):
        fail("claims", f"aud {aud}, want {ENV['CLIENT_ID']}")
    if not claims.get("exp", 0) > time.time():
        fail("claims", f"exp {claims.get('exp')} is not in the future")
    ok("claims", f"iss {issuer}, aud = client id, email/preferred_username/groups in id_token and userinfo")

    # The code, taken by this browser before the relying party can have it, presented with
    # the wrong client secret. The session from the sign-in above is still live.
    state = "probe"
    q = urllib.parse.urlencode({"response_type": "code", "client_id": ENV["CLIENT_ID"],
                                "redirect_uri": ENV["REDIRECT_URI"], "scope": "openid",
                                "state": state})
    cb = arrive(b, "client-auth", f"{ORIGIN}/application/o/authorize/?{q}", ENV["REDIRECT_URI"],
                sign_in(member, ENV["USER_PASSWORD"]))
    code = urllib.parse.parse_qs(urllib.parse.urlsplit(cb).query).get("code", [None])[0]
    if not code:
        fail("client-auth", f"no code in {cb}")
    wrong = base64.b64encode(f"{ENV['CLIENT_ID']}:not-the-secret".encode()).decode()
    status, _, raw = b.request("POST", f"{ORIGIN}/application/o/token/",
                               {"grant_type": "authorization_code", "code": code,
                                "redirect_uri": ENV["REDIRECT_URI"]},
                               form=True, headers={"Authorization": f"Basic {wrong}"})
    err = json.loads(raw).get("error") if raw.startswith(b"{") else raw[:100]
    if status == 200 or err != "invalid_client":
        fail("client-auth", f"token endpoint answered a wrong client secret with HTTP {status} {err}")
    ok("client-auth", f"wrong client secret refused: HTTP {status} {err}")

    # A user outside the bound group signs in fine, but the application's policy binding must
    # stop the authorization: no code may reach the relying party. authentik renders the
    # refusal as an HTTP 200 page, so the page is identified as that refusal rather than
    # accepting any non-redirect (a 500 is not a denial).
    b = Browser()
    kind, got = follow(b, "access-policy", f"{rp}/", f"{rp}/auth/callback",
                       sign_in(outsider, ENV["USER_PASSWORD"]))
    if kind == "arrived":
        fail("access-policy", f"{outsider} (not in {ENV['GROUP']}) was sent to the client with {got}")
    if kind != "page" or got[0] != 200 or not re.search(rb"<title>\s*Permission denied", got[2]):
        fail("access-policy", f"{outsider} stopped somewhere other than the denial page: {kind} {str(got)[:300]}")
    ok("access-policy", f"{outsider} (not in {ENV['GROUP']}) refused at {urllib.parse.urlsplit(got[1]).path}")


if __name__ == "__main__":
    {"setup": setup, "login": login}[sys.argv[1]]()
