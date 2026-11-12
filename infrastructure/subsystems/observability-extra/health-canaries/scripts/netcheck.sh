#!/bin/sh
# Pod networking and cluster DNS canary. Resolves the netcheck-echo headless Service through
# cluster DNS, then fetches /node from every address it returns. Each echo pod answers with the
# name of the node it runs on, so a reply proves the right pod answered, not just that something
# at that address did. Exits non-zero if DNS returns nothing or any address does not answer.
#
# The Service publishes not-ready addresses, so an echo pod that is running but unreachable
# stays in the answer and fails this check rather than silently dropping out of it. A node with
# no echo pod at all is not visible from here; NetcheckEchoNotOnEveryNode covers that.
#
# Runs on busybox: nslookup, wget and awk are its applets.
set -eu

# The first search domain is "<namespace>.svc.<cluster domain>", so the FQDN is built from
# resolv.conf rather than assuming the cluster domain. busybox nslookup does not apply the
# search list itself.
search_domain="$(awk '$1 == "search" { print $2; exit }' /etc/resolv.conf)"
if [ -z "$search_domain" ]; then
  echo "FAIL: no search domain in /etc/resolv.conf"
  exit 1
fi
name="${NETCHECK_SERVICE}.${search_domain}"

# Answer addresses follow the "Name:" line; the "Address:" lines before it are the server's.
addresses="$(nslookup -type=a "$name" 2>/dev/null | awk '/^Name:/ { answers = 1 } answers && /^Address/ { print $NF }')" || true
if [ -z "$addresses" ]; then
  echo "FAIL: DNS returned no addresses for ${name}"
  exit 1
fi

failed=0
total=0
for address in $addresses; do
  total=$((total + 1))
  node=""
  for _ in 1 2; do
    if node="$(wget -q -T 5 -O - "http://${address}:${NETCHECK_PORT}/node" 2>/dev/null)" && [ -n "$node" ]; then
      break
    fi
    node=""
  done
  if [ -n "$node" ]; then
    echo "ok: ${address} answered from node ${node}"
  else
    echo "FAIL: ${address} did not answer on port ${NETCHECK_PORT} (2 attempts, 5s each)"
    failed=$((failed + 1))
  fi
done

echo "checked ${total} echo pods from node ${NODE_NAME}, ${failed} failed"
[ "$failed" -eq 0 ]
