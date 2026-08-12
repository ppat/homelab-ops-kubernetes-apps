#!/usr/bin/env bash
# H6: does Terraform 1.6.6's S3 backend work against Garage for state storage? Sequence:
#   1. init with a local backend, apply the dummy resources (establishes a known-good state
#      and a baseline `plan` -- "no changes" -- to compare against after migration)
#   2. switch main.tf to the s3 backend (Garage), `terraform init -migrate-state`
#   3. `terraform plan` against the migrated state and confirm it still reports no diff
# Falsifier (per the brief): any state operation failing, or a plan differing from the
# MinIO-backed (here: local-backed, since MinIO isn't in scope for this repo) equivalent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR=/opt/build-scratch/h6-workdir
CONTAINER=h6-garage
DATA_ROOT=/opt/build-scratch/h6-data
RPC_SECRET="a7d0754a5ceaded2ceaeaeda44864637004a3d58aa844f4177c0b833463a4c32"
S3_PORT=16900
OUT="$HERE/../results/h6-terraform.json"
mkdir -p "$(dirname "$OUT")"

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
sudo rm -rf "$DATA_ROOT" "$WORKDIR"
mkdir -p "$DATA_ROOT/meta" "$DATA_ROOT/data" "$WORKDIR"

# --- terraform 1.6.6, pinned exactly ---
if ! command -v terraform >/dev/null || [ "$(terraform version -json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null)" != "1.6.6" ]; then
  echo "fetching terraform 1.6.6..."
  curl -sSL -o /tmp/tf166.zip https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
  sudo mkdir -p /opt/terraform-1.6.6
  sudo unzip -o -q /tmp/tf166.zip -d /opt/terraform-1.6.6
  sudo ln -sf /opt/terraform-1.6.6/terraform /usr/local/bin/terraform
fi
terraform version

# --- garage instance + bucket for state ---
cat > /tmp/h6-garage.toml <<EOF
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "lmdb"
metadata_fsync = true
replication_factor = 1
rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "$RPC_SECRET"

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage.localhost"

[admin]
api_bind_addr = "[::]:3903"
EOF

docker run -d --name "$CONTAINER" \
  -v /tmp/h6-garage.toml:/etc/garage.toml:ro \
  -v "$DATA_ROOT/meta":/var/lib/garage/meta \
  -v "$DATA_ROOT/data":/var/lib/garage/data \
  -p "$S3_PORT:3900" \
  dxflrs/garage:v2.3.0 >/dev/null
for _ in $(seq 1 30); do docker exec "$CONTAINER" /garage status >/dev/null 2>&1 && break; sleep 1; done

NODE_ID=$(docker exec "$CONTAINER" /garage node id -q | cut -d@ -f1)
docker exec "$CONTAINER" /garage layout assign -z dc1 -c 1G "$NODE_ID" >/dev/null
docker exec "$CONTAINER" /garage layout apply --version 1 >/dev/null
docker exec "$CONTAINER" /garage bucket create h6falsify >/dev/null
docker exec "$CONTAINER" /garage key create h6-key >/dev/null
docker exec "$CONTAINER" /garage bucket allow --read --write --owner h6falsify --key h6-key >/dev/null
INFO=$(docker exec "$CONTAINER" /garage key info h6-key --show-secret)
ACCESS=$(echo "$INFO" | grep "Key ID:" | awk '{print $NF}')
SECRET=$(echo "$INFO" | grep "Secret key:" | awk '{print $NF}')

cd "$WORKDIR"
cp "$HERE/main-local-backend.tf" main.tf

echo "=== step 1: init + apply with a LOCAL backend (baseline) ==="
terraform init -input=false | tail -5
terraform apply -auto-approve -input=false | tail -10
set +e  # -detailed-exitcode returns 2 for "there are changes" -- not a script failure, a result to capture
terraform plan -input=false -detailed-exitcode > /tmp/h6-baseline-plan.txt 2>&1
baseline_rc=$?
set -e
echo "baseline plan exit code: $baseline_rc (0=no changes expected)"

echo "=== step 2: switch to the Garage S3 backend, migrate state ==="
cp "$HERE/main.tf" "$WORKDIR/main.tf"  # restore the s3 backend block
set +e
# -force-copy auto-confirms the state-copy prompt non-interactively (the alternative,
# piping "yes" to stdin, does not work: terraform refuses to prompt at all when
# -input=false is also set, which we want to keep for a genuinely unattended run).
terraform init -migrate-state -force-copy \
  -backend-config="access_key=$ACCESS" \
  -backend-config="secret_key=$SECRET" \
  > /tmp/h6-migrate.txt 2>&1
migrate_rc=$?
set -e
tail -15 /tmp/h6-migrate.txt
echo "migrate rc: $migrate_rc (0=success expected)"

echo "=== step 3: plan against the migrated (Garage-backed) state ==="
set +e
terraform plan -input=false -detailed-exitcode > /tmp/h6-migrated-plan.txt 2>&1
migrated_rc=$?
set -e
tail -15 /tmp/h6-migrated-plan.txt
echo "migrated plan exit code: $migrated_rc (0=no changes expected, matching baseline)"

VERDICT="PASS"
[ "$migrate_rc" -eq 0 ] || VERDICT="FAIL-migrate"
[ "$migrated_rc" -eq 0 ] || VERDICT="FAIL-plan-diff"

cat > "$OUT" <<EOF
{
  "baseline_plan_rc": $baseline_rc,
  "migrate_rc": $migrate_rc,
  "migrated_plan_rc": $migrated_rc,
  "verdict": "$VERDICT"
}
EOF
echo "SUMMARY test=h6-terraform-backend verdict=$VERDICT"
cat "$OUT"
