#!/usr/bin/env bash
# H4-C: does H4's instrument (du on data_dir) even apply to this estate's dominant object
# shape? Production is 3.44M objects, 95.4% under 1 KB, mean 3.9 KB. Garage stores any object
# smaller than INLINE_THRESHOLD = 3072 B inline in the metadata DB and creates NO block and NO
# BlockRef (src/block/manager.rs:44, src/api/s3/put.rs). If that is right, `du` on data_dir is
# structurally blind to 95.4% of this workload -- in BOTH the original H4 and the H4-B retest,
# which used 1 MiB objects exclusively.
set -euo pipefail
C=h4c-garage; DR=/opt/build-scratch/h4c-data; P=15940; A=15943
RPC="a7d0754a5ceaded2ceaeaeda44864637004a3d58aa844f4177c0b833463a4c32"
cleanup(){ docker rm -f "$C" >/dev/null 2>&1 || true; }
trap cleanup EXIT; cleanup
sudo rm -rf "$DR"; mkdir -p "$DR/meta" "$DR/data"
cat > /tmp/h4c-garage.toml <<EOF
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "lmdb"
metadata_fsync = true
replication_factor = 1
rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "$RPC"
[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage.localhost"
[admin]
api_bind_addr = "[::]:3903"
EOF
docker run -d --name "$C" -v /tmp/h4c-garage.toml:/etc/garage.toml:ro \
  -v "$DR/meta":/var/lib/garage/meta -v "$DR/data":/var/lib/garage/data \
  -p "$P:3900" -p "$A:3903" dxflrs/garage:v2.3.0 >/dev/null
for _ in $(seq 1 30); do docker exec "$C" /garage status >/dev/null 2>&1 && break; sleep 1; done
NID=$(docker exec "$C" /garage node id -q | cut -d@ -f1)
docker exec "$C" /garage layout assign -z dc1 -c 1G "$NID" >/dev/null
docker exec "$C" /garage layout apply --version 1 >/dev/null
docker exec "$C" /garage bucket create h4c >/dev/null
docker exec "$C" /garage key create h4c-key >/dev/null
docker exec "$C" /garage bucket allow --read --write --owner h4c --key h4c-key >/dev/null
I=$(docker exec "$C" /garage key info h4c-key --show-secret)
AK=$(echo "$I" | grep "Key ID:" | awk '{print $NF}'); SK=$(echo "$I" | grep "Secret key:" | awk '{print $NF}')

python3 - "$P" "$AK" "$SK" "$DR" "$C" <<'PY'
import sys, json, subprocess, concurrent.futures, os
import boto3
from botocore.config import Config
port, ak, sk, dr, cont = sys.argv[1:6]
c = boto3.client("s3", endpoint_url=f"http://127.0.0.1:{port}", aws_access_key_id=ak,
                 aws_secret_access_key=sk, config=Config(s3={"addressing_style":"path"},
                 max_pool_connections=32), region_name="garage")
du = lambda p: int(subprocess.run(["sudo","du","-sb",p],capture_output=True,text=True,check=True).stdout.split()[0])
def snap(label):
    d = {"label":label, "data_dir_du":du(f"{dr}/data"), "meta_dir_du":du(f"{dr}/meta"),
         "keys": c.list_objects_v2(Bucket="h4c").get("KeyCount",0)}
    print(f"  {label:24s} data_dir={d['data_dir_du']:>12,}  meta_dir={d['meta_dir_du']:>12,}  keys={d['keys']}", flush=True)
    return d
R={}
print("baseline (empty):", flush=True); R["empty"]=snap("empty")

N=20000; SIZE=512   # 512 B < INLINE_THRESHOLD(3072) -> should be stored inline, no block
print(f"PUT {N} x {SIZE}B objects (sub-inline-threshold, the production shape)...", flush=True)
def put(i): c.put_object(Bucket="h4c", Key=f"small/{i:06d}", Body=os.urandom(SIZE))
with concurrent.futures.ThreadPoolExecutor(24) as ex: list(ex.map(put, range(N)))
R["after_small"]=snap("after 20k x 512B")

N2=200; SIZE2=1024*1024  # 1 MiB > threshold -> real blocks, for contrast
print(f"PUT {N2} x 1MiB distinct objects (above threshold, for contrast)...", flush=True)
def put2(i): c.put_object(Bucket="h4c", Key=f"big/{i:05d}", Body=os.urandom(SIZE2))
with concurrent.futures.ThreadPoolExecutor(8) as ex: list(ex.map(put2, range(N2)))
R["after_big"]=snap("after +200 x 1MiB")

small_bytes = N*SIZE; big_bytes = N2*SIZE2
d_small_data = R["after_small"]["data_dir_du"] - R["empty"]["data_dir_du"]
d_small_meta = R["after_small"]["meta_dir_du"] - R["empty"]["meta_dir_du"]
d_big_data   = R["after_big"]["data_dir_du"]  - R["after_small"]["data_dir_du"]
print(f"\n  20,000 x 512B = {small_bytes:,} B written -> data_dir grew {d_small_data:,} B, meta_dir grew {d_small_meta:,} B")
print(f"     200 x 1MiB  = {big_bytes:,} B written -> data_dir grew {d_big_data:,} B")
R["small_objects_bypass_data_dir"] = d_small_data < small_bytes*0.10
R["big_objects_hit_data_dir"] = d_big_data > big_bytes*0.80
print(f"\n  INLINE CONFIRMED (sub-3KB objects do not land in data_dir): {R['small_objects_bypass_data_dir']}")
print(f"  BLOCKS CONFIRMED (>3KB objects do land in data_dir):        {R['big_objects_hit_data_dir']}")
print(f"\n  => du(data_dir), H4's assertion (3), is {'BLIND' if R['small_objects_bypass_data_dir'] else 'sensitive'} "
      f"to the 95.4%% of this estate's objects that are <1KB.")
print(json.dumps({k:v for k,v in R.items() if not isinstance(v,dict)}))
st = subprocess.run(["docker","exec",cont,"/garage","stats"],capture_output=True,text=True).stdout
print("\n".join(l for l in st.splitlines() if any(w in l for w in ("Objects","Block","block","Table","object","version"))) [:1500])
PY
