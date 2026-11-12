#!/bin/sh
# FreeBSD/amd64 test VM for --os=freebsd (feature-port-freebsd-native).
#
#   tools/vm/freebsd.sh fetch     download + verify FreeBSD 15.1 qcow2, one-time key setup
#   tools/vm/freebsd.sh start     boot headless (ssh on 127.0.0.1:$PXX_FBSD_PORT)
#   tools/vm/freebsd.sh run BIN [ARGS...]   copy BIN in, run it, relay stdout/stderr/exit
#   tools/vm/freebsd.sh stop
#
# The image lives in $PXX_VM_DIR/freebsd (default /data/vm/freebsd) -- several
# GB, keep it off a small root filesystem. Needs qemu-system-x86_64 (+KVM),
# xz, python3-pexpect.
set -e
VMDIR="${PXX_VM_DIR:-/data/vm}/freebsd"
PORT="${PXX_FBSD_PORT:-2223}"
REL=15.1-RELEASE
IMG=FreeBSD-$REL-amd64-BASIC-CLOUDINIT-ufs.qcow2
URL=https://download.freebsd.org/releases/VM-IMAGES/$REL/amd64/Latest
SSHO="-q -i $VMDIR/id_vm -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=$VMDIR/known_hosts -o ConnectTimeout=5"

case "$1" in
fetch)
  mkdir -p "$VMDIR"; cd "$VMDIR"
  [ -f fbsd.qcow2 ] && { echo "already have $VMDIR/fbsd.qcow2"; exit 0; }
  curl -sSfO "$URL/$IMG.xz"; curl -sSf "$URL/CHECKSUM.SHA256" -o CHECKSUM.SHA256
  want=$(grep "($IMG.xz)" CHECKSUM.SHA256 | grep -o '[0-9a-f]\{64\}')
  [ "$(sha256sum "$IMG.xz" | cut -d' ' -f1)" = "$want" ] || { echo "checksum mismatch"; exit 1; }
  unxz "$IMG.xz"; mv "$IMG" fbsd.qcow2; qemu-img resize -q fbsd.qcow2 20G
  [ -f id_vm ] || ssh-keygen -q -t ed25519 -N "" -C pxx-vm -f id_vm
  # The image's root has no console password; install the key over serial
  # (the cloud-init seed route did not take on 15.1) and allow key-only root.
  python3 "$(dirname "$0")/fbsd_setup.py" "$VMDIR"
  ;;
start)
  cd "$VMDIR"
  [ -f vm.pid ] && kill -0 "$(cat vm.pid)" 2>/dev/null && exit 0
  qemu-system-x86_64 -enable-kvm -m 2048 -smp 2 -display none -daemonize \
    -pidfile vm.pid -serial file:console.log \
    -drive file=fbsd.qcow2,if=virtio,format=qcow2 \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22 -device virtio-net-pci,netdev=n0 2>/dev/null
  i=0; until ssh $SSHO -p "$PORT" root@127.0.0.1 true 2>/dev/null; do
    i=$((i+1)); [ $i -gt 60 ] && { echo "VM did not come up"; exit 1; }; sleep 3; done
  ;;
run)
  shift; bin="$1"; shift
  scp $SSHO -P "$PORT" "$bin" root@127.0.0.1:/tmp/pxxbin >/dev/null || exit 125
  ssh $SSHO -p "$PORT" root@127.0.0.1 "chmod +x /tmp/pxxbin && cd /tmp && /tmp/pxxbin $*"
  ;;
stop)
  ssh $SSHO -p "$PORT" root@127.0.0.1 "shutdown -p now" 2>/dev/null || true
  ;;
*) sed -n '2,12p' "$0"; exit 2 ;;
esac
