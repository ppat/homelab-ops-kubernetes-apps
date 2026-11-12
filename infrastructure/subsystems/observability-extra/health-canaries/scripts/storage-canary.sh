#!/bin/sh
# Storage canary. Writes random data to the mounted volume with O_DIRECT and an fsync, reads it
# back with O_DIRECT and compares its SHA-256 with the checksum of the stream that was written.
#
# What each step rules out:
#   - the mountpoint check: a mount that silently fell through, so the write landed in the
#     container's own filesystem instead of the volume;
#   - the expected checksum is taken from the generated stream, never from the file, so a read
#     that returns what the kernel cached cannot agree with itself;
#   - O_DIRECT on both sides bypasses the page cache, so the read-back comes from the device or
#     the NFS server, and conv=fsync makes the write fail if the data cannot be made durable.
#
# Runs on busybox: dd (oflag/iflag=direct, conv=fsync), sha256sum, mkfifo and mountpoint are
# its applets.
set -eu

dir="${STORAGE_CANARY_DIR}"
bytes_mib="${STORAGE_CANARY_MIB}"
file="${dir}/health-canary-${POD_NAME}"
fifo="/tmp/stream.fifo"

cleanup() {
  rm -f "$file" "$fifo" /tmp/expected
}
trap cleanup EXIT

if ! mountpoint -q "$dir"; then
  echo "FAIL: ${dir} is not a mount point, the volume is not mounted"
  exit 1
fi

start="$(date +%s)"
mkfifo "$fifo"
sha256sum < "$fifo" > /tmp/expected &
checksum_pid=$!
if ! head -c "$((bytes_mib * 1024 * 1024))" /dev/urandom \
  | tee "$fifo" \
  | dd of="$file" bs=1M iflag=fullblock oflag=direct conv=fsync 2>/dev/null; then
  echo "FAIL: writing ${bytes_mib} MiB with O_DIRECT and fsync to ${dir} failed"
  exit 1
fi
wait "$checksum_pid"
expected="$(cut -d' ' -f1 /tmp/expected)"
written="$(date +%s)"

if ! actual="$(dd if="$file" bs=1M iflag=direct 2>/dev/null | sha256sum | cut -d' ' -f1)"; then
  echo "FAIL: reading ${file} back with O_DIRECT failed"
  exit 1
fi
read_back="$(date +%s)"

if [ "$actual" != "$expected" ]; then
  echo "FAIL: read-back checksum ${actual} does not match written ${expected}"
  exit 1
fi

echo "ok: ${bytes_mib} MiB written, fsynced and read back intact on ${dir} from node ${NODE_NAME}" \
  "(write $((written - start))s, read $((read_back - written))s)"
