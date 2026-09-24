#!/bin/sh
# Runs INSIDE the capability-probe Job pod (alpine/openssl: busybox + openssl), not on the
# chainsaw runner. validate-capabilities.yaml mounts it, beside a copy of the trust bundle
# (/probe/bundle.pem), as a ConfigMap, mounts the probe-tls Secret at /tls, and binds every
# expected value into the environment from live state.
#
# One line per leg, `CAP OK   [<leg>] ...` or `CAP FAIL [<leg>] ...`. Every leg runs even
# after a failure, so one run shows every broken capability; the exit is 1 if any failed.
#   cert-sans      the issued certificate carries exactly the Certificate's dnsNames
#   cert-validity  it verifies against the issuer's ca.crt (signature, validity window,
#                  hostname) and spans exactly spec.duration
#   cert-key       tls.key is the private half of tls.crt
#   trust          the trust-manager bundle verifies bitwarden-sdk-server's certificate for
#                  the name the ClusterSecretStore dials, and the server answers /ready
#   trust-control  a CA that did not sign that server is rejected -- without this, `trust`
#                  passing could mean verification was never enforced
set -u
T0=$(date +%s)
FAILED=0
ok() { echo "CAP OK   [$1] $2 (t+$(( $(date +%s) - T0 ))s)"; }
fail() { echo "CAP FAIL [$1] $2 (t+$(( $(date +%s) - T0 ))s)"; FAILED=1; }
oneline() { tr '\n' ' ' <"$1"; }

# ---- cert-manager: what a consumer mounting the Secret receives ----------------------------
got_sans=$(openssl x509 -in /tls/tls.crt -noout -ext subjectAltName 2>/dev/null \
  | tail -n +2 | tr ',' '\n' | sed 's/^ *//' | sort | tr '\n' ' ')
want_sans=$(for n in $EXPECT_SANS; do echo "DNS:$n"; done | sort | tr '\n' ' ')
if [ -n "$got_sans" ] && [ "$got_sans" = "$want_sans" ]; then
  ok cert-sans "$got_sans"
else
  fail cert-sans "certificate has '${got_sans}', Certificate asks for '${want_sans}'"
fi

first_san=${EXPECT_SANS%% *}
if openssl verify -CAfile /tls/ca.crt -verify_hostname "$first_san" /tls/tls.crt \
    >/tmp/verify 2>&1; then
  epoch() {
    openssl x509 -in /tls/tls.crt -noout "-$1" -dateopt iso_8601 \
      | sed 's/^[^=]*=//; s/Z$//' | xargs -I{} date -u -d {} +%s
  }
  span=$(( $(epoch enddate) - $(epoch startdate) ))
  if [ "$span" = "$EXPECT_DURATION_S" ]; then
    ok cert-validity "verifies against ca.crt for $first_san, spans ${span}s"
  else
    fail cert-validity "spans ${span}s, Certificate asks for ${EXPECT_DURATION_S}s"
  fi
else
  fail cert-validity "$(oneline /tmp/verify)"
fi

if [ "$(openssl x509 -in /tls/tls.crt -noout -pubkey 2>&1)" = \
     "$(openssl pkey -in /tls/tls.key -pubout 2>&1)" ]; then
  ok cert-key "tls.key matches tls.crt"
else
  fail cert-key "tls.key is not the key of tls.crt"
fi

# ---- trust-manager: the bundle, used the way external-secrets uses it ----------------------
# -no-CApath/-no-CAstore: the image's system roots must not be able to rescue a bad bundle.
dial() {
  printf 'GET /ready HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n' "$SDK_HOST" \
    | openssl s_client -connect "$SDK_HOST:$SDK_PORT" -servername "$SDK_HOST" \
        -verify_hostname "$SDK_HOST" -verify_return_error -CAfile "$1" \
        -no-CApath -no-CAstore -quiet >/tmp/resp 2>/tmp/err
}

end=$(( $(date +%s) + TLS_BUDGET_S ))
while :; do
  if dial /probe/bundle.pem && head -n 1 /tmp/resp | grep -q '^HTTP/1\.[01] 200'; then
    ok trust "bundle verifies $SDK_HOST:$SDK_PORT, /ready -> $(head -n 1 /tmp/resp | tr -d '\r')"
    break
  fi
  if [ "$(date +%s)" -ge "$end" ]; then
    fail trust "$(oneline /tmp/err)| $(head -n 1 /tmp/resp)"
    break
  fi
  sleep 3
done

# The probe's own certificate is a valid CA-of-itself that never signed the server. The
# failure must be a verification failure; a refused connection would prove nothing.
if dial /tls/ca.crt; then
  fail trust-control "a CA that did not sign $SDK_HOST was accepted"
elif grep -qi 'verify' /tmp/err; then
  ok trust-control "unrelated CA rejected: $(grep -i -m 1 'verify' /tmp/err)"
else
  fail trust-control "did not fail on verification: $(oneline /tmp/err)"
fi

exit "$FAILED"
