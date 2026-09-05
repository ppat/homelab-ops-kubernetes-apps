#!/bin/sh
set -eu

# `change-bucket-owner` DESTROYS the bucket's ACL and policy, so ownership is
# reassigned only when the observed owner differs. And there is EXACTLY ONE
# delete path, scoped to accounts: deleting a credential is reversible, deleting
# a bucket is not, and this store holds the only copy of every backup.
for var in ADMIN_ENDPOINT_URL ADMIN_ACCESS_KEY_ID ADMIN_SECRET_ACCESS_KEY ADMIN_REGION \
  VERSITYGW_PLAN VERSITYGW_READY_DEADLINE_SECONDS; do
  eval "value=\${$var:-}"
  [ -n "$value" ] || { echo "FAIL: $var is not set" >&2; exit 1; }
done
[ -r "$VERSITYGW_PLAN" ] || { echo "FAIL: plan ${VERSITYGW_PLAN} is not readable" >&2; exit 1; }

admin() { versitygw admin "$@"; }

deadline=$(( $(date +%s) + VERSITYGW_READY_DEADLINE_SECONDS ))
until admin list-users >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL: admin API at ${ADMIN_ENDPOINT_URL} did not answer within ${VERSITYGW_READY_DEADLINE_SECONDS}s" >&2
    admin list-users >&2 || true
    exit 1
  fi
  sleep 5
done
echo "ok: admin API at ${ADMIN_ENDPOINT_URL} is answering"

ensure_account() {
  access="$1"; secret="$2"; role="$3"
  if admin list-users | awk 'NR > 2 { print $1 }' | grep -qxF "$access"; then
    admin update-user --access "$access" --secret "$secret" --role "$role"
    echo "converged account ${access} (role ${role})"
  else
    admin create-user --access "$access" --secret "$secret" --role "$role"
    echo "created account ${access} (role ${role})"
  fi
}

ensure_bucket() {
  bucket="$1"; owner="$2"
  current="$(admin list-buckets | awk -v b="$bucket" 'NR > 2 && $1 == b { print $2 }')"
  if [ -z "$current" ]; then
    admin create-bucket --bucket "$bucket" --owner "$owner"
    echo "created bucket ${bucket} owned by ${owner}"
  elif [ "$current" != "$owner" ]; then
    admin change-bucket-owner --bucket "$bucket" --owner "$owner"
    echo "reassigned bucket ${bucket} from ${current} to ${owner}"
  else
    echo "bucket ${bucket} already owned by ${owner}"
  fi
}

accounts=0
buckets=0
while IFS="$(printf '\t')" read -r kind a b c; do
  [ -n "$kind" ] || continue
  case "$kind" in
  account)
    ensure_account "$a" "$b" "$c"
    accounts=$((accounts + 1))
    ;;
  bucket)
    ensure_bucket "$a" "$b"
    buckets=$((buckets + 1))
    ;;
  *)
    echo "FAIL: unrecognised plan row kind '${kind}'" >&2
    exit 1
    ;;
  esac
done < "$VERSITYGW_PLAN"

if [ "$accounts" -eq 0 ] || [ "$buckets" -eq 0 ]; then
  echo "FAIL: the plan produced ${accounts} account(s) and ${buckets} bucket(s); a store with" >&2
  echo "      neither is never the intended state." >&2
  exit 1
fi

desired_accounts="$(awk -F'\t' '$1 == "account" { print $2 }' "$VERSITYGW_PLAN")"
removed=0
for existing in $(admin list-users | awk 'NR > 2 { print $1 }'); do
  if ! printf '%s\n' "$desired_accounts" | grep -qxF "$existing"; then
    admin delete-user --access "$existing"
    echo "removed account ${existing} -- no longer declared"
    removed=$((removed + 1))
  fi
done

echo "provisioning complete: ${accounts} account(s), ${buckets} bucket(s), ${removed} account(s) removed"

echo "--- buckets the gateway holds after this run ---"
admin list-buckets
