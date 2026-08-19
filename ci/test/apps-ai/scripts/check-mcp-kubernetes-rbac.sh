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

  kubectl port-forward -n ai svc/mcp-kubernetes-sandbox "${port}:8080" \
    >/tmp/mcp-kubernetes-sandbox-port-forward.log 2>&1 &
  local pf_pid=$!
  trap 'kill "$pf_pid" >/dev/null 2>&1 || true' RETURN

  local attempt=0
  until curl -fsS "${base}/healthz" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then
      echo "FAIL: mcp-kubernetes-sandbox never answered /healthz through the port-forward" >&2
      FAILED=1
      return
    fi
    sleep 1
  done

  local init_headers
  init_headers=$(mktemp)
  curl -fsS -D "$init_headers" -o /dev/null "${base}/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"chainsaw-write-boundary-check","version":"0"}}}'

  local session
  session=$(grep -i '^Mcp-Session-Id:' "$init_headers" | tr -d '\r' | awk '{print $2}')
  rm -f "$init_headers"
  if [ -z "$session" ]; then
    echo "FAIL: no Mcp-Session-Id returned from mcp-kubernetes-sandbox's /mcp initialize" >&2
    FAILED=1
    return
  fi

  curl -fsS -o /dev/null "${base}/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "Mcp-Session-Id: ${session}" \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'

  # WRITE direction: this is read_only = false's entire point. A ConfigMap in the
  # cluster's built-in "default" namespace, not a new Namespace -- avoids depending on
  # namespace-deletion finalizers settling within this step's timeout.
  local create_response
  create_response=$(curl -fsS "${base}/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "Mcp-Session-Id: ${session}" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"resources_create_or_update","arguments":{"resource":"apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: chainsaw-write-boundary-check\n  namespace: default\ndata:\n  probe: \"true\"\n"}}}')
  if echo "$create_response" | grep -q 'created or updated successfully'; then
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
  secret_response=$(curl -fsS "${base}/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "Mcp-Session-Id: ${session}" \
    -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"resources_list","arguments":{"apiVersion":"v1","kind":"Secret","namespace":"kube-system"}}}') || curl_rc=$?
  if [ "${curl_rc}" -ne 0 ] || [ -z "${secret_response}" ]; then
    echo "FAIL: could not ask -- the resources_list(Secret) call itself failed (curl rc=${curl_rc}, response empty=$([ -z "${secret_response}" ] && echo yes || echo no))." >&2
    echo "      This is NOT evidence that denied_resources failed open. It is evidence the probe could not run." >&2
    FAILED=1
  elif echo "$secret_response" | grep -q '"isError":true' && echo "$secret_response" | grep -q 'resource not allowed'; then
    echo "ok: resources_list(Secret) was denied by denied_resources, despite read_only = false"
  else
    echo "FAIL: resources_list(Secret) was ALLOWED -- denied_resources did not hold. Got: $secret_response" >&2
    FAILED=1
  fi

  # Best-effort cleanup so a re-run of this step doesn't depend on the prior run's probe
  # object; failure here doesn't fail the step, since the assertions above already ran.
  curl -fsS -o /dev/null "${base}/mcp" \
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
