#!/bin/bash

# For the liveness probe, we're testing 2 things:
#   1) dns resolution by upstream server
#   2) dns resolution by pihole itself
# If either fails, we want the pihole container to be restarted.
#   1) restarting when upstream dns resolution fails,
#      - allows kubernetes to set the upstream server's ip address as an environment variable
#        for service discovery by entrypoint script.
#      - so if upstream server's service ip changed, then this restart and reset of upstream host
#        ip should fix that problem. a restart of this pod is only way, a new value will be set
#        for that environment variable.
#           See: https://kubernetes.io/docs/concepts/services-networking/service/#environment-variables
#   2) additionally if pihole itself can't resolve DNS, then a restart could potentially
#      solve that issue.

UPSTREAM_HOST=$(cat /var/run/pihole/__upstream_current)
dig +short +retry=0 @$UPSTREAM_HOST cloudflare.com
dig +short +retry=0 +norecurse '@127.0.0.1' pi.hole
