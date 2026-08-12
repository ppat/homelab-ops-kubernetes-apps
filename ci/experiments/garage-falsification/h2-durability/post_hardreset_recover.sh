#!/usr/bin/env bash
# H2 hard-reset mechanic, step 2 of 4 (renumbered from the original 3-step plan -- see
# ../README.md "A finding about this VM itself"). A REAL `echo b > /proc/sysrq-trigger`
# reset on this sandbox VM does not come back the way a normal reboot would: the VM's own
# cloud-init `runcmd` (which bind-mounts /opt/docker-install, /opt/build-scratch, and
# /var/lib/containerd out from under the PVC onto their working paths) is a cloud-init
# FIRST-BOOT-ONLY step, so none of those bind mounts are back after a genuine reboot --
# dockerd fails to start (its binary lives behind one of them) and, critically, if you start
# the H2 containers before re-establishing the H2 substrate mounts (iSCSI login, NFS mount,
# tmpfs+loop), Docker silently auto-creates empty directories at the missing mount points and
# Garage happily bootstraps a brand-new empty cluster there -- which would masquerade as
# "everything survived as an empty-but-healthy node" while actually meaning "the real data is
# sitting unreachable under the real mount, once it comes back". This script does the fix, in
# the order that avoids that trap: restore the docker-critical bind mounts and start docker
# FIRST, but do NOT touch the H2 containers until the H2 substrates (iSCSI/NFS/tmpfs-loop) are
# confirmed remounted.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== restoring docker-critical bind mounts ==="
sudo mount --bind /var/lib/docker/.install /opt/docker-install 2>/dev/null || true
sudo mount --bind /var/lib/docker/.build-scratch /opt/build-scratch 2>/dev/null || true
sudo mount --bind /var/lib/docker/.containerd /var/lib/containerd 2>/dev/null || true
sudo mount --bind /var/lib/docker/.cache /var/cache 2>/dev/null || true
sudo mount --bind /var/lib/docker/.log /var/log 2>/dev/null || true
sudo mount --bind /var/lib/docker/.apt-lists /var/lib/apt/lists 2>/dev/null || true
for p in /opt/docker-install /opt/build-scratch /var/lib/containerd; do
  mountpoint -q "$p" || { echo "FATAL: $p did not come back"; exit 1; }
done
# Retried, not one-shot: immediately post-reboot this raced containerd's own startup once
# during development (containerd.service was only ~13s into starting) and failed with no
# journal entry explaining why -- a plain retry after `reset-failed` was sufficient, so that's
# what this does rather than something more elaborate.
for attempt in 1 2 3; do
  sudo systemctl reset-failed docker >/dev/null 2>&1 || true
  sudo systemctl restart docker && break
  echo "docker restart attempt $attempt failed, retrying..."
  sleep 3
done
for _ in $(seq 1 20); do systemctl is-active --quiet docker && break; sleep 1; done
systemctl is-active --quiet docker || { echo "FATAL: docker did not become active"; exit 1; }
echo "docker OK"

# CRITICAL ORDERING: any H2 containers docker auto-started via --restart unless-stopped at
# this point would be bootstrapping fresh state onto the NOT-YET-remounted substrate paths --
# stop them before substrates.sh runs, exactly the mistake this script's header describes
# catching on iteration 1.
docker stop $(docker ps --filter "name=h2-" -q) 2>/dev/null || true

echo "=== restoring H2 substrates (iSCSI login, NFS mount, tmpfs+loop) ==="
bash "$HERE/substrates.sh"

echo "=== starting H2 containers now that substrates are confirmed mounted ==="
docker start $(docker ps -a --filter "name=h2-" -q)
sleep 3
docker ps --filter "name=h2-" --format "{{.Names}}: {{.Status}}" | sort
