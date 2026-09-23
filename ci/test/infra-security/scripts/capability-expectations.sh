#!/bin/sh
# Runs on the chainsaw runner. Prints, as one JSON object, the live values the in-cluster
# probe (capability-probe.sh) must observe: the Certificate's own spec, i.e. intent. The
# trust bundle reaches the probe as a file instead; see capability-probe-configmap.sh.
# Exits non-zero naming the first value that is empty: a probe bound to an empty
# expectation could only ever fail, and would fail with a misleading message.
set -eu

sans=$(kubectl -n security-probe get certificate probe-tls -o jsonpath='{.spec.dnsNames[*]}')
duration=$(kubectl -n security-probe get certificate probe-tls -o jsonpath='{.spec.duration}')

# A Go duration as the API returns it ("2160h" or "2160h0m0s") in seconds.
duration_s=$(echo "$duration" | awk '{
  s = 0; n = $0
  if (match(n, /[0-9]+h/)) s += substr(n, RSTART, RLENGTH - 1) * 3600
  if (match(n, /[0-9]+m/)) s += substr(n, RSTART, RLENGTH - 1) * 60
  if (match(n, /[0-9]+s/)) s += substr(n, RSTART, RLENGTH - 1)
  if (s > 0) print s
}')

for name in sans duration_s; do
  eval "value=\${$name}"
  # shellcheck disable=SC2154 # assigned by the eval above
  [ -n "$value" ] || { echo "capability-expectations: $name is empty" >&2; exit 1; }
done

printf '{"sans":"%s","duration_s":"%s"}\n' "$sans" "$duration_s"
