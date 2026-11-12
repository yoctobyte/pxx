#!/bin/sh
# OpenBSD/amd64 test VM (feature-port-libc-family-openbsd-netbsd-minix).
#
#   tools/vm/openbsd.sh start     boot headless (ssh on 127.0.0.1:$PXX_OBSD_PORT)
#   tools/vm/openbsd.sh run BIN [ARGS...]   copy BIN in, run it, relay stdout/stderr/exit
#   tools/vm/openbsd.sh ssh [CMD]  a shell (or one command) in the VM
#   tools/vm/openbsd.sh stop
#
# The VM lives in $PXX_VM_DIR/openbsd (default /data/vm/openbsd): obsd.qcow2,
# id_vm (ssh key for root), known_hosts. It was installed unattended from the
# stock install80.iso (the install.py there drives the serial console); there
# is no fetch step yet. Needs qemu-system-x86_64 with KVM.
set -e
VMDIR="${PXX_VM_DIR:-/data/vm}/openbsd"
PORT="${PXX_OBSD_PORT:-2222}"
SSHO="-q -i $VMDIR/id_vm -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=$VMDIR/known_hosts -o ConnectTimeout=5"

case "$1" in
  start)
    [ -f "$VMDIR/obsd.qcow2" ] || { echo "no $VMDIR/obsd.qcow2" >&2; exit 1; }
    if [ -f "$VMDIR/vm.pid" ] && kill -0 "$(cat "$VMDIR/vm.pid")" 2>/dev/null; then
      echo "already running"; exit 0
    fi
    qemu-system-x86_64 -enable-kvm -m 2048 -smp 2 -display none -daemonize \
      -pidfile "$VMDIR/vm.pid" -serial file:"$VMDIR/console.log" \
      -drive file="$VMDIR/obsd.qcow2",if=virtio,format=qcow2 \
      -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22 -device virtio-net-pci,netdev=n0
    i=0; until ssh $SSHO -p "$PORT" root@127.0.0.1 true 2>/dev/null; do
      i=$((i+1)); [ $i -lt 90 ] || { echo "no ssh after 180s" >&2; exit 1; }; sleep 2
    done
    echo "up on port $PORT" ;;
  run)
    shift; b="$1"; shift
    scp $SSHO -P "$PORT" "$b" root@127.0.0.1:/tmp/pxxbin.new >/dev/null || exit 125
    ssh $SSHO -p "$PORT" root@127.0.0.1 "mv -f /tmp/pxxbin.new /tmp/pxxbin && chmod +x /tmp/pxxbin && cd /tmp && /tmp/pxxbin $*" ;;
  ssh)
    shift; exec ssh $SSHO -p "$PORT" root@127.0.0.1 "$@" ;;
  stop)
    ssh $SSHO -p "$PORT" root@127.0.0.1 "halt -p" || true ;;
  *)
    sed -n '2,12p' "$0"; exit 2 ;;
esac
