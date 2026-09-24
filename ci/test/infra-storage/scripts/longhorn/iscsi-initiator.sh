#!/bin/bash
set -euo pipefail

# Gives the kind node a working iSCSI initiator, which longhorn's v1 data engine needs to
# attach any volume: the engine exports each volume as an iSCSI target (tgtd, inside
# instance-manager) and logs the node in to it through `iscsiadm`, which drives `iscsid`,
# which drives the kernel. Without this every attach ends in `FailedAttachVolume ...
# DeadlineExceeded` and no pod can use a longhorn volume at all.
#
# Runs on the CI runner (the docker host), not in the cluster. Each line below closes one
# gap between a kind node and a real one, and each was found by the failure it leaves:
#
# - iscsid in the HOST network namespace. The kernel's iSCSI control channel (the
#   NETLINK_ISCSI socket) exists only in the initial network namespace -- it is absent from
#   a kind node's /proc/net/netlink -- so an iscsid inside the node starts cleanly and then
#   dies at its first login with `sendmsg: bug? ctrl_fd`. Hence a sibling container with
#   --net=host.
# - ...and in the NODE's pid namespace. Longhorn runs iscsiadm by nsenter-ing into the
#   mount and network namespaces of whichever process is named `iscsid` in its /host/proc
#   (the mechanism that exists for Talos, whose iscsid runs in its own container), so the
#   daemon must be visible there. --pid=container:<node> also ties its lifetime to the node.
#   It runs the node's own image, so the initiator is the node's own open-iscsi build, and
#   `mkdir /run/lock` is because iscsiadm cannot create /run/lock/iscsi without it.
# - The host's own iscsid stopped: GitHub's ubuntu runners ship iscsid.socket active, and it
#   holds the abstract IPC socket that iscsid binds (`Can not bind IPC socket`).
# - A route from the host to the node's pod CIDR, because the initiator now connects from
#   the host to the target on instance-manager's pod IP.
# - A NetworkPolicy admitting the host to instance-manager on 3260. The chart's
#   `networkPolicies.restrictInternalTraffic` (on by default) admits only longhorn's own pods
#   to instance-manager. On a real node the initiator is the node itself, and node-local
#   traffic is exempt under k3s's policy controller; here it arrives from the docker host's
#   address, which kindnet's policy enforcement drops.
# - /sys remounted read-write inside the node. Kind mounts it read-only, and longhorn writes
#   the new disk's /sys/block/<dev>/device/timeout at attach (`read-only file system`).
#
# The runner is ephemeral, so nothing here is undone. On a long-lived docker host this
# leaves the host's iscsid.socket stopped and a route to a pod CIDR behind. Every consumer
# the suite starts has exited by the end of a passing run, so no volume is attached at
# teardown; after a failure one may be, and then the host kernel's I/O to a target that died
# with the node blocks the node container's exit for iscsid's replacement_timeout (120s).
# The session then stays in the host kernel in state FAILED and cannot be logged out
# (iscsiadm error 32, target not connected); later clusters on that host were observed to
# attach normally alongside it.

node_count="$(kubectl get nodes -o name | wc -l)"
if [ "$node_count" -ne 1 ]; then
  # Every step below targets one node container; on more nodes the others would still
  # have no initiator and the attach would fail wherever the volume landed.
  echo "LONGHORN FAIL [initiator] this preparation handles exactly one kind node, found ${node_count}"
  exit 1
fi
node="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
node_ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$node")"
pod_cidr="$(kubectl get node "$node" -o jsonpath='{.spec.podCIDR}')"
node_image="$(docker inspect -f '{{.Config.Image}}' "$node")"
host_ip="$(ip -4 route get "$node_ip" | sed -n 's/.* src \([0-9.]*\).*/\1/p')"
if [ -z "$node_ip" ] || [ -z "$pod_cidr" ] || [ -z "$node_image" ] || [ -z "$host_ip" ]; then
  echo "LONGHORN FAIL [initiator] could not read node_ip='${node_ip}' pod_cidr='${pod_cidr}' image='${node_image}' host_ip='${host_ip}'"
  exit 1
fi

sudo -n modprobe iscsi_tcp
sudo -n systemctl stop iscsid.socket iscsid.service 2>/dev/null || true
sudo -n ip route replace "$pod_cidr" via "$node_ip"
docker exec "$node" mount -o remount,rw /sys

docker rm -f "${node}-iscsid" >/dev/null 2>&1 || true
docker run -d --rm --name "${node}-iscsid" --privileged --net=host --pid="container:${node}" \
  --entrypoint /bin/sh "$node_image" -c 'mkdir -p /run/lock && exec /usr/sbin/iscsid -f' >/dev/null

# iscsiadm exits 21 (no active sessions) when it reached the daemon and 20 when it could not.
# Waiting for that, rather than for the container to be running, is what makes "the daemon is
# up" a fact before the first attach depends on it.
deadline=$(( $(date +%s) + 30 ))
while :; do
  rc=0
  docker exec "${node}-iscsid" iscsiadm -m session >/dev/null 2>&1 || rc=$?
  { [ "$rc" -eq 0 ] || [ "$rc" -eq 21 ]; } && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "LONGHORN FAIL [initiator] iscsid did not answer iscsiadm within 30s (last rc=${rc})"
    docker logs "${node}-iscsid" 2>&1 | tail -20 || true
    exit 1
  fi
  sleep 1
done

kubectl apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ci-host-iscsi-initiator
  namespace: longhorn-system
spec:
  podSelector:
    matchLabels:
      longhorn.io/component: instance-manager
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: ${host_ip}/32
    ports:
    - protocol: TCP
      port: 3260
EOF

echo "LONGHORN OK   [initiator] iscsid (${node_image}) answering for node ${node}; host ${host_ip} routes ${pod_cidr} via ${node_ip}"
