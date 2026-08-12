#!/usr/bin/env bash
# H2 substrate provisioning: sets up the 4 mount points the durability matrix's 12 cells
# live on. Idempotent -- safe to re-run after a hard reset (some of this, e.g. the iSCSI
# login and NFS mount, does not survive a reboot and must be redone).
#
# Substrates (see ../README.md for why each one is here):
#   ext4-local  -- control. A plain directory on /var/lib/docker's own ext4 volume (vdb).
#   ext4-iscsi  -- the proposed sidestep. A REAL iSCSI target (LIO/targetcli, kernel
#                  target_core_mod) exported and logged into from the SAME host (no second
#                  iSCSI host was available in this environment -- see README "Environment
#                  constraints"). This still exercises the real SCSI command path
#                  (SYNCHRONIZE_CACHE/FUA on fsync), which is the thing under test.
#   nfsv4.1     -- the incumbent. Same loopback-host caveat as iSCSI: a real nfs-kernel-server
#                  export, mounted via the real NFSv4.1 client on the same host.
#   tmpfs-loop  -- fast negative control. ext4 on a loop device backed by a file living on
#                  tmpfs. A hard reset must destroy this substrate's data outright (tmpfs is
#                  never written to disk) -- if any cell on this substrate reports CLEAN after
#                  a hard reset, the test's power-loss mechanic isn't really losing the page
#                  cache and every hard-reset result in this run is void.
set -euo pipefail

ROOT=/opt/build-scratch/h2-substrates
ISCSI_BACKING="$ROOT/iscsi-backing.img"
ISCSI_IQN="iqn.2026-08.local.garage-falsify:h2"
NFS_EXPORT_DIR="$ROOT/nfs-export"
TMPFS_BACKING_DIR=/mnt/h2-tmpfs-backing
TMPFS_LOOP_IMG="$TMPFS_BACKING_DIR/loop.img"

mkdir -p "$ROOT"
sudo mkdir -p /mnt/h2-ext4-local /mnt/h2-ext4-iscsi /mnt/h2-nfsv4.1
sudo chown "$(id -u)":"$(id -g)" /mnt/h2-ext4-local /mnt/h2-ext4-iscsi /mnt/h2-nfsv4.1

echo "=== ext4-local ==="
echo "ok: $(df -h /mnt/h2-ext4-local | tail -1)"

echo "=== ext4-iscsi (LIO loopback) ==="
if ! mountpoint -q /mnt/h2-ext4-iscsi; then
  if [ ! -f "$ISCSI_BACKING" ]; then
    truncate -s 6G "$ISCSI_BACKING"
  fi
  # Idempotent LIO config: wipe and rebuild every time substrates.sh runs (cheap, avoids
  # stale-state edge cases after a hard reset where targetcli's saveconfig didn't survive).
  sudo targetcli /backstores/fileio delete h2backing >/dev/null 2>&1 || true
  sudo targetcli /iscsi delete "$ISCSI_IQN" >/dev/null 2>&1 || true
  sudo targetcli /backstores/fileio create h2backing "$ISCSI_BACKING"
  sudo targetcli /iscsi create "$ISCSI_IQN"
  sudo targetcli "/iscsi/$ISCSI_IQN/tpg1/luns" create /backstores/fileio/h2backing
  sudo targetcli "/iscsi/$ISCSI_IQN/tpg1" set attribute authentication=0 demo_mode_write_protect=0 generate_node_acls=1
  sudo targetcli "/iscsi/$ISCSI_IQN/tpg1/portals" create 127.0.0.1 3260 >/dev/null 2>&1 || true

  sudo iscsiadm -m discovery -t sendtargets -p 127.0.0.1:3260 >/dev/null
  sudo iscsiadm -m node --targetname "$ISCSI_IQN" --portal 127.0.0.1:3260 --login
  sleep 2
  DEV=$(readlink -f /dev/disk/by-path/*"$ISCSI_IQN"*lun-0 2>/dev/null | head -1)
  if [ -z "$DEV" ]; then
    # fall back: newest scsi disk that isn't vda/vdb/vdc
    DEV=$(lsblk -ndo NAME,TRAN | awk '$2=="iscsi"{print "/dev/"$1}' | tail -1)
  fi
  echo "iscsi device: $DEV"
  if ! sudo blkid "$DEV" >/dev/null 2>&1; then
    sudo mkfs.ext4 -q -F "$DEV"
  fi
  sudo mount "$DEV" /mnt/h2-ext4-iscsi
  sudo chown "$(id -u)":"$(id -g)" /mnt/h2-ext4-iscsi
fi
echo "ok: $(df -h /mnt/h2-ext4-iscsi | tail -1)"

echo "=== nfsv4.1 (loopback nfs-kernel-server) ==="
mkdir -p "$NFS_EXPORT_DIR"
if ! grep -q "$NFS_EXPORT_DIR" /etc/exports 2>/dev/null; then
  # "sync" (not "async"): the export must not itself lie about durability -- the whole
  # point of this substrate is testing whether GARAGE's metadata_fsync matters, which
  # requires the NFS server to honestly honor COMMIT/stable writes rather than
  # pre-acknowledging everything from its own write-back buffer.
  echo "$NFS_EXPORT_DIR 127.0.0.1(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports >/dev/null
  sudo exportfs -ra
  sudo systemctl restart nfs-kernel-server
fi
if ! mountpoint -q /mnt/h2-nfsv4.1; then
  sudo mount -t nfs4 -o vers=4.1 127.0.0.1:"$NFS_EXPORT_DIR" /mnt/h2-nfsv4.1
fi
sudo chown "$(id -u)":"$(id -g)" "$NFS_EXPORT_DIR"
echo "ok: $(df -h /mnt/h2-nfsv4.1 | tail -1)"

echo "=== tmpfs-loop (ext4 on a loop device backed by a tmpfs file) ==="
if ! mountpoint -q "$TMPFS_BACKING_DIR"; then
  sudo mkdir -p "$TMPFS_BACKING_DIR"
  sudo mount -t tmpfs -o size=3g tmpfs "$TMPFS_BACKING_DIR"
fi
if ! mountpoint -q /mnt/h2-tmpfs-loop; then
  sudo mkdir -p /mnt/h2-tmpfs-loop
  if [ ! -f "$TMPFS_LOOP_IMG" ]; then
    sudo truncate -s 2G "$TMPFS_LOOP_IMG"
    sudo mkfs.ext4 -q -F "$TMPFS_LOOP_IMG"
  fi
  LOOPDEV=$(sudo losetup --show -f "$TMPFS_LOOP_IMG")
  sudo mount "$LOOPDEV" /mnt/h2-tmpfs-loop
fi
sudo chown "$(id -u)":"$(id -g)" /mnt/h2-tmpfs-loop
echo "ok: $(df -h /mnt/h2-tmpfs-loop | tail -1)"

echo "=== all substrates ready ==="
mount | grep -E "h2-ext4-iscsi|h2-nfsv4.1|h2-tmpfs-loop"
