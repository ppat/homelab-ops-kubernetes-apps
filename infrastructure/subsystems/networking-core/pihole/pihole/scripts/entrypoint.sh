#!/bin/bash
set -eo pipefail

UPSTREAM_PORT="53"


retry() {
  local -r -i max_attempts="$1"; shift
  # shellcheck disable=SC2124
  local -r cmd="$@"
  local -i attempt=1

  until /usr/bin/timeout -v 3s $cmd 2>&1; do
    if (( attempt == max_attempts )); then
      echo "Attempt $attempt failed and there are no more attempts left!"
      return 1
    fi

    local sleep_seconds=$(( attempt ** 2 ))
    echo "Attempt $attempt failed! Trying again in $sleep_seconds seconds..."
    attempt=$(( attempt + 1 ))
    sleep $sleep_seconds
  done
}

wait_till_upstream() {
  local -r upstream_host="$1"
  local -r upstream_name="$2"

  echo "Checking connectivity..."
  if retry 3 nc -z -v -w 1 $upstream_host $UPSTREAM_PORT 2>&1 | sed -E 's|(.*)|    \1|g'; then
    echo "Checking dns resolution..."
    retry 3 dig @$upstream_host cloudflare.com | sed -E 's|(.*)|    \1|g'
    echo "Upstream $upstream_name is resolving dns successfully..."
  else
    echo "Cannot connect to upstream $upstream_name ($upstream_host)."
    return 1
  fi
}

validate_and_set_upstream() {
  local -r upstream_host="$1"
  local -r upstream_name="$2"
  local -r upstream_type="$3"

  echo "upstream/($upstream_type): $upstream_name ($upstream_host):"
  echo "  Upstream dns service configured by kubrnetes service discovery at this service IP..."
  echo "  Adding upstream to /etc/hosts..."
  echo -e "$upstream_host\t$upstream_name" >> /etc/hosts
  echo $upstream_host > /var/run/pihole/__upstream_$upstream_type
  echo "  Validating upstream dns service..."
  if wait_till_upstream $upstream_host $upstream_name 2>&1 | sed -E 's|(.*)|    \1|g'; then
    if [[ -e /var/run/pihole/__upstream_current ]]; then
      echo "  An upstream has already been set, skipping for this upstream..."
    else
      echo "  No upstream has been set yet..."
      echo "  Directing pihole to use $upstream_type upstream ($upstream_name)..."
      ln -sf /var/run/pihole/__upstream_$upstream_type /var/run/pihole/__upstream_current
      export PIHOLE_DNS_="${upstream_host}"
      echo "  Done."
    fi
  else
    return 1
  fi
}

configure_upstream() {
  local -i upstream_count=0

  if [[ ! -z "${UNBOUND_SERVICE_HOST}" ]]; then
    if validate_and_set_upstream "${UNBOUND_SERVICE_HOST}" "unbound-recursive" "primary"; then
      upstream_count=$((upstream_count+1))
    fi
  fi
  echo
  if [[ ! -z "${CLOUDFLARED_DOH_SERVICE_HOST}" ]]; then
    if validate_and_set_upstream "${CLOUDFLARED_DOH_SERVICE_HOST}" "cloudflare-doh" "secondary"; then
      upstream_count=$((upstream_count+1))
    fi
  fi
  echo
  echo "$upstream_count upstreams are available..."
  if (( upstream_count == 0 )); then
    echo "All upstreams failed validation..."
    echo "Cannot proceed without an upstream DNS server..."
    echo "Exiting..."
    echo
    exit 1
  fi
}

main() {
  echo "Detecting and configuring pihole upstream based on kubernetes service env vars..."
  echo
  configure_upstream
  echo
  if [[ ! -z "${REV_SERVER_TARGET}" ]]; then
    echo "Configuring router ($REV_SERVER_TARGET) in /etc/hosts..."
    echo -e "$REV_SERVER_TARGET\trouter" >> /etc/hosts
    echo
  fi
  echo "Starting pihole..."
  exec /s6-init
}

main
