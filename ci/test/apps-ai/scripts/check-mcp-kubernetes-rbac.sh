#!/bin/bash
set -euo pipefail

# Makes pre-requisites/mcp-kubernetes-rbac.yaml (a hand-synced copy of the ClusterRole
# the clusters repo actually binds -- see that file's header comment) load-bearing:
# nothing else in this suite asserts what the mcp-kubernetes-homelab / mcp-kubernetes-nas
# identities can actually reach, so a fixture that silently drifted permissive would
# still pass CI. This runs "kubectl auth can-i --as=<identity>" checks against both and
# fails on any mismatch.
#
# mcp-kubernetes-sandbox is checked differently, in two parts, because its production
# security model genuinely differs from the read-only pair above rather than just being a
# write-capable variant of the same shape: its real credential is a cluster-admin
# ServiceAccount token minted inside the sandbox Talos cluster's own guest etcd
# (homelab-ops-kubernetes-experiments, provision-agent-admin-cronjob.yaml), not a
# hand-maintained scoped ClusterRole this repo controls. RBAC therefore grants that
# identity everything -- check_sandbox_identity below asserts exactly that, on purpose,
# rather than binding a fictional scoped role that would pass CI while testing nothing
# true about production. The boundary that actually matters for this server (Secrets stay
# unreadable despite read_only = false) is enforced by mcp-kubernetes-sandbox-config's own
# denied_resources, not RBAC, so it's checked separately in
# check_sandbox_write_boundary, at the protocol level, against the deployed pod --
# invoked with --sandbox-write-boundary once that Deployment is Ready (see
# chainsaw-test.yaml's "Verify mcp-kubernetes-sandbox write boundary" step; running it
# any earlier would just fail to reach the pod).

FAILED=0

# Subresources MUST be passed as --subresource=x, never as "resource/x": kubectl splits
# that shorthand into resource + resource NAME, so "get nodes/proxy" asks whether the
# identity can get a Node object literally named "proxy" -- which the blanket nodes grant
# allows, making the check silently pass or fail for reasons unrelated to the subresource.
#
# check <identity> <verb> <resource> <expected: yes|no> [extra kubectl-auth-can-i args...]
check() {
  local identity="$1" verb="$2" resource="$3" expected="$4"
  shift 4
  local result
  if kubectl auth can-i "$verb" "$resource" --as="$identity" "$@" >/dev/null 2>&1; then
    result="yes"
  else
    result="no"
  fi
  if [ "$result" != "$expected" ]; then
    echo "FAIL: --as=$identity can-i $verb $resource $* => got '$result', expected '$expected'" >&2
    FAILED=1
  else
    echo "ok: --as=$identity can-i $verb $resource $* => $result"
  fi
}

check_identity() {
  local identity="$1"

  # Must be denied: Secrets, exec/delete/patch write paths, RBAC/token escalation
  # oracles, and nodes/proxy (the kubelet-proxy grant dropped for being exec-equivalent
  # -- GET routes it exposes include /exec, /attach, /portForward).
  check "$identity" get secrets no --all-namespaces
  check "$identity" list secrets no -n ai
  check "$identity" create pods no --subresource=exec --all-namespaces
  check "$identity" delete pods no --all-namespaces
  check "$identity" create subjectaccessreviews no
  check "$identity" create tokenreviews no
  check "$identity" patch deployments no --all-namespaces
  check "$identity" get nodes no --subresource=proxy
  # generators.external-secrets.io is granted as an explicit kind list rather than "*"
  # precisely to keep these two out: fakes.spec.data is literal plaintext key/value
  # pairs and webhooks.spec.headers can carry an inline API key. A regression to "*"
  # would silently re-grant both, so assert them individually.
  check "$identity" get fakes.generators.external-secrets.io no --all-namespaces
  check "$identity" get webhooks.generators.external-secrets.io no --all-namespaces
  # Excluded for the same reason, one level removed: ClusterGenerator.spec inlines
  # fakeSpec/webhookSpec, and GeneratorState.spec.resource/state snapshot a generator
  # manifest and its output -- both can carry the same plaintext a kind-level fakes/
  # webhooks deny is meant to block, just wrapped in a different kind.
  check "$identity" get clustergenerators.generators.external-secrets.io no --all-namespaces
  check "$identity" get generatorstates.generators.external-secrets.io no --all-namespaces

  # Must be allowed: the read-only surface the MCP tools actually rely on.
  check "$identity" list nodes yes
  check "$identity" get pods yes --subresource=log --all-namespaces
  check "$identity" list customresourcedefinitions yes
  check "$identity" list persistentvolumes yes
  check "$identity" list storageclasses yes
  check "$identity" create selfsubjectaccessreviews yes
}

# See the file-level comment above for why this identity's expectations are "yes" across
# the board, including for Secrets -- that's the real production shape (cluster-admin),
# not a gap in this check.
check_sandbox_identity() {
  local identity="$1"

  check "$identity" get secrets yes --all-namespaces
  check "$identity" create pods yes --subresource=exec --all-namespaces
  check "$identity" delete pods yes --all-namespaces
  check "$identity" create namespaces yes
  check "$identity" patch deployments yes --all-namespaces
  check "$identity" create tokenreviews yes
}

# Protocol-level check against the deployed mcp-kubernetes-sandbox pod: proves the
# denied_resources boundary in mcp-kubernetes-sandbox-config actually holds, which
# check_sandbox_identity above cannot do (RBAC allows the same read it's about to prove
# denied). Talks streamable-HTTP MCP directly over a port-forward, mirroring what LiteLLM
# itself does against this server in production -- there's no lighter-weight interface
# this server exposes for CRUD/tool calls.
check_sandbox_write_boundary() {
  local port=18080
  local base="http://127.0.0.1:${port}"
  # Bounds every /mcp request below. Without a per-request cap a server that accepts the
  # connection and never answers blocks inside curl forever, so this step's own `timeout`
  # does the killing -- and the run is then reported as "the write-boundary assertion ran out
  # of budget" rather than "the Secret probe never returned". On a security control those read
  # very differently: the first invites raising a budget, the second says the control was
  # never exercised. See issue #3724.
  #
  # 20s is derived from the two deadlines this sits between, not copied from a sibling script.
  # Floor: the MCP server gives the Kubernetes API ten seconds of its own, and that deadline is
  # known to be reached under rollout load (see the comment above this step in
  # ../chainsaw-test.yaml). A request that spends ten seconds upstream and comes back with a
  # "context deadline exceeded" tool error IS an answer, and the branches below handle it --
  # so the cap must sit clear of it rather than converting it into "could not ask".
  # Ceiling: the step allows 2m. Readiness can spend 40s of that, and past the handshake the
  # longest continuing chain is three bounded calls (write probe, Secret read, cleanup), since
  # a failed write probe deliberately does NOT return. 40 + 3x20 = 100s, inside 2m with room
  # for port-forward setup.
  #
  # A cap is safe here only because every call is request/response: each POSTs one JSON-RPC
  # message and the server closes after replying. Nothing below opens a long-lived stream, so
  # no bound can truncate one.
  local CURL_MAX_TIME=20

  kubectl port-forward -n ai svc/mcp-kubernetes-sandbox "${port}:8080" \
    >/tmp/mcp-kubernetes-sandbox-port-forward.log 2>&1 &
  local pf_pid=$!
  trap 'kill "$pf_pid" >/dev/null 2>&1 || true' RETURN

  # A pure reachability probe on an already-forwarded local port, not a tool call, so it takes
  # a much tighter bound than CURL_MAX_TIME -- nothing upstream of the pod is involved and a
  # healthy answer is immediate.
  #
  # Bounded by WALL CLOCK rather than by attempt count, because the two only agree while the
  # probe returns instantly. Counting attempts was a proxy for "give it 30 seconds" that held
  # exactly as long as each curl failed fast (connection refused while the port-forward comes
  # up). Once a request can legitimately occupy 10s, 30 attempts buys 30 x (10 + 1) = 330s --
  # longer than this step's entire 2m budget, so a slow-but-answering endpoint would consume
  # the whole step here and the write boundary would never be probed at all.
  local ready=0 ready_deadline
  ready_deadline=$(( $(date +%s) + 30 ))
  while [ "$(date +%s)" -lt "${ready_deadline}" ]; do
    if curl -fsS --max-time 10 "${base}/healthz" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  if [ "${ready}" -ne 1 ]; then
    echo "FAIL: mcp-kubernetes-sandbox never answered /healthz through the port-forward" >&2
    FAILED=1
    return
  fi

  # Every curl here is rc-captured rather than left to `set -e`. An unguarded transport failure
  # kills the function BEFORE the Secret assertion runs, silently and with a non-1 exit code --
  # which is the same defect as the one the Secret probe below documents, in a worse position:
  # it cancels the security check rather than mislabelling it.
  local init_headers rc=0
  init_headers=$(mktemp)
  curl -fsS --max-time "${CURL_MAX_TIME}" -D "$init_headers" -o /dev/null "${base}/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"chainsaw-write-boundary-check","version":"0"}}}' || rc=$?
  if [ "${rc}" -ne 0 ]; then
    echo "FAIL: could not ask -- /mcp initialize failed (curl rc=${rc}). Not evidence about any control." >&2
    rm -f "$init_headers"
    FAILED=1
    return
  fi

  # `|| true` is load-bearing. grep exits 1 when the header is absent and `set -o pipefail`
  # propagates that, so under `set -e` the assignment killed the function one line before its
  # own guard -- leaving the guard below as unreachable dead code and producing NO output at
  # all. Reproduced: empty stdout, empty stderr, exit 1, security assertion never reached.
  local session
  session=$(grep -i '^Mcp-Session-Id:' "$init_headers" | tr -d '\r' | awk '{print $2}' || true)
  rm -f "$init_headers"
  if [ -z "$session" ]; then
    echo "FAIL: no Mcp-Session-Id returned from mcp-kubernetes-sandbox's /mcp initialize" >&2
    FAILED=1
    return
  fi

  rc=0
  curl -fsS --max-time "${CURL_MAX_TIME}" -o /dev/null "${base}/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "Mcp-Session-Id: ${session}" \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' || rc=$?
  if [ "${rc}" -ne 0 ]; then
    echo "FAIL: could not ask -- notifications/initialized failed (curl rc=${rc}). Not evidence about any control." >&2
    FAILED=1
    return
  fi

  # WRITE direction: this is read_only = false's entire point. A ConfigMap in the
  # cluster's built-in "default" namespace, not a new Namespace -- avoids depending on
  # namespace-deletion finalizers settling within this step's timeout.
  local create_response create_rc=0
  create_response=$(curl -fsS --max-time "${CURL_MAX_TIME}" "${base}/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "Mcp-Session-Id: ${session}" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"resources_create_or_update","arguments":{"resource":"apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: chainsaw-write-boundary-check\n  namespace: default\ndata:\n  probe: \"true\"\n"}}}') || create_rc=$?
  if [ "${create_rc}" -ne 0 ]; then
    echo "FAIL: could not ask -- resources_create_or_update failed (curl rc=${create_rc}). Not evidence about any control." >&2
    FAILED=1
  elif echo "$create_response" | grep -q 'created or updated successfully'; then
    echo "ok: resources_create_or_update (ConfigMap) succeeded through mcp-kubernetes-sandbox"
  else
    echo "FAIL: resources_create_or_update did not report success: $create_response" >&2
    FAILED=1
  fi

  # FAILING direction: the control that matters most. RBAC (check_sandbox_identity above)
  # already allows this read outright -- only mcp-kubernetes-sandbox-config's own
  # denied_resources stands between read_only = false and a readable Secret.
  #
  # Three outcomes, not two. `curl -fsS` returning nothing -- port-forward dropped, pod gone,
  # apiserver unreachable -- used to fall into the same branch as a successful-but-allowed read
  # and print "was NOT denied", which reads as the security control failing OPEN when in fact the
  # probe never ran. That is the most misleading direction a security check can fail in, so
  # "could not ask" is now its own outcome and says so.
  local secret_response curl_rc=0
  secret_response=$(curl -fsS --max-time "${CURL_MAX_TIME}" "${base}/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "Mcp-Session-Id: ${session}" \
    -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"resources_list","arguments":{"apiVersion":"v1","kind":"Secret","namespace":"kube-system"}}}') || curl_rc=$?
  # `-z` alone asks "is it empty", which is not the question. An SSE keepalive or a bare framing
  # line is non-empty and carries no answer, and would have routed to ALLOWED -- reporting the
  # control as failed open on a response that never addressed it. Require something that is
  # actually a JSON-RPC reply before believing either verdict. This can only move a case from
  # ALLOWED to could-not-ask, never the reverse, so it cannot manufacture a pass.
  if [ "${curl_rc}" -ne 0 ] || [ -z "${secret_response}" ] || ! echo "${secret_response}" | grep -q '"jsonrpc"'; then
    echo "FAIL: could not ask -- the resources_list(Secret) call did not return a JSON-RPC reply" >&2
    echo "      (curl rc=${curl_rc}, ${#secret_response} bytes returned)." >&2
    echo "      This is NOT evidence that denied_resources failed open. It is evidence the probe could not run." >&2
    FAILED=1
  # The GVK is pinned, not just the phrase. A bare `resource not allowed` would accept a denial
  # issued for some other resource, and the safety of the `"isError":true` half rests on Go's
  # json.Marshal escaping quotes inside tool text -- an invariant of the pinned image, not
  # something this script arranges. Pinning the GVK is what stops an upstream response-shape
  # change from being read as this control holding.
  #
  # Read off the real server rather than assumed -- the denial body is
  #   ...\"failed to list resources: Get \\\"https://kubernetes.default.svc/api/v1/namespaces/
  #   kube-system/secrets\\\": resource not allowed: /v1, Kind=Secret\"...,\"isError\":true
  # and this pattern matches both observed denial bodies and neither observed allow body.
  #
  # If upstream rewords it, this goes RED rather than quietly passing -- which is the correct
  # direction for a security assertion to fail.
  elif echo "$secret_response" | grep -q '"isError":true' && echo "$secret_response" | grep -q 'resource not allowed: /v1, Kind=Secret'; then
    echo "ok: resources_list(Secret) was denied by denied_resources, despite read_only = false"
  else
    # The body is deliberately NOT printed here. This branch means the read may have SUCCEEDED,
    # so the response can carry Secret material -- and this repository is public, which makes
    # its CI logs world-readable. Printing it would turn a contained control failure into a
    # disclosure. Reproduce locally to see the body.
    echo "FAIL: resources_list(Secret) was ALLOWED -- denied_resources did not hold." >&2
    echo "      ${#secret_response} bytes returned; body withheld because it may contain Secret" >&2
    echo "      material and CI logs for this repository are public." >&2
    FAILED=1
  fi

  # Best-effort cleanup so a re-run of this step doesn't depend on the prior run's probe
  # object; failure here doesn't fail the step, since the assertions above already ran.
  #
  # Bounded anyway, and being best-effort is the reason rather than an exception to it: this is
  # the one call whose result nobody reads, so a hang here kills the step on its timeout after
  # every verdict has already been printed -- turning a run that proved the control holds into
  # a red attributed to a budget. Same cap as the calls above, because it is the same kind of
  # tool call and a shorter one risks abandoning a delete that would have succeeded.
  curl -fsS --max-time "${CURL_MAX_TIME}" -o /dev/null "${base}/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "Mcp-Session-Id: ${session}" \
    -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"resources_delete","arguments":{"apiVersion":"v1","kind":"ConfigMap","namespace":"default","name":"chainsaw-write-boundary-check"}}}' \
    || true
}

if [ "${1:-}" = "--sandbox-write-boundary" ]; then
  check_sandbox_write_boundary
  if [ "$FAILED" -ne 0 ]; then
    echo "mcp-kubernetes-sandbox write-boundary check failed (see FAIL lines above)" >&2
    exit 1
  fi
  exit 0
fi

check_identity "system:serviceaccount:ai:mcp-kubernetes-homelab"
check_identity "system:serviceaccount:mcp-access:mcp-kubernetes-nas"
check_sandbox_identity "system:serviceaccount:mcp-access:mcp-kubernetes-sandbox"

if [ "$FAILED" -ne 0 ]; then
  echo "one or more mcp-kubernetes RBAC checks failed (see FAIL lines above)" >&2
  exit 1
fi
