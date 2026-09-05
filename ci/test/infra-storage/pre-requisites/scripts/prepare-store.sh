#!/bin/sh
set -eu

: "${VERSITYGW_STORE_ROOT:?VERSITYGW_STORE_ROOT must be set}"

umask 022
cat > "${VERSITYGW_STORE_ROOT}/.versitygw-store-identity" <<'IDENTITY'
store=versitygw-chainsaw
store_id=00000000000000000000000000000001
prepared=2026-01-01T00:00:00Z
gateway_root=data
IDENTITY

cat "${VERSITYGW_STORE_ROOT}/.versitygw-store-identity"
