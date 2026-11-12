#!/bin/sh
# NetBSD/amd64 test VM (feature-port-libc-family-openbsd-netbsd-minix).
#
#   tools/vm/netbsd.sh start     boot headless (ssh on 127.0.0.1:$PXX_NBSD_PORT)
#   tools/vm/netbsd.sh run BIN [ARGS...]   copy BIN in, run it, relay stdout/stderr/exit
#   tools/vm/netbsd.sh ssh [CMD]  a shell (or one command) in the VM
#   tools/vm/netbsd.sh stop
#
# The VM lives in $PXX_VM_DIR/netbsd (default /data/vm/netbsd): nbsd.qcow2,
# vars.fd (its UEFI variables), id_vm (ssh key for root), known_hosts. It is
# the stock NetBSD-11.1-amd64-live.img with /EFI/NetBSD/boot.cfg on the EFI
# partition set to consdev=com0, then set up over the serial console (sshd,
# dhcpcd, a root key). Boots under OVMF. Needs qemu-system-x86_64 with KVM.
set -e
VMDIR="${PXX_VM_DIR:-/data/vm}/netbsd"
PORT="${PXX_NBSD_PORT:-2227}"
OVMF="${PXX_OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}"
SSHO="-q -i $VMDIR/id_vm -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=$VMDIR/known_hosts -o ConnectTimeout=5"
case "$1" in
  start)
    [ -f "$VMDIR/nbsd.qcow2" ] || { echo "no $VMDIR/nbsd.qcow2" >&2; exit 1; }
    if [ -f "$VMDIR/vm.pid" ] && kill -0 "$(cat "$VMDIR/vm.pid")" 2>/dev/null; then
      echo "already running"; exit 0
    fi
    qemu-system-x86_64 -enable-kvm -m 2048 -smp 2 -display none -daemonize \
      -pidfile "$VMDIR/vm.pid" -serial file:"$VMDIR/console.log" \
      -drive if=pflash,format=raw,readonly=on,file="$OVMF" \
      -drive if=pflash,format=raw,file="$VMDIR/vars.fd" \
      -drive file="$VMDIR/nbsd.qcow2",if=virtio,format=qcow2 \
      -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22 -device virtio-net-pci,netdev=n0
    i=0; until ssh $SSHO -p "$PORT" root@127.0.0.1 true 2>/dev/null; do
      i=$((i+1)); [ $i -lt 90 ] || { echo "no ssh after 180s" >&2; exit 1; }; sleep 2
    done
    echo "up on port $PORT" ;;
  run)
    shift; b="$1"; shift
    scp $SSHO -P "$PORT" "$b" root@127.0.0.1:/tmp/pxxbin.new >/dev/null || exit 125
    # PXX_TEST_* variables are forwarded, as tools/vm/freebsd.sh does.
    envs=$(env | grep '^PXX_TEST_[A-Za-z0-9_]*=' | sed "s/'/'\\\\''/g; s/=\(.*\)/='\1'/" | tr '\n' ' ')
    # Linux's default 8 MB stack, so a stack-overflow test takes the same path.
    pre="mv -f /tmp/pxxbin.new /tmp/pxxbin && chmod +x /tmp/pxxbin && cd /tmp && ulimit -s 8192 &&"
    # PXX_VM_PTY=1 runs it on a real tty: ssh -tt inside a local script(1).
    if [ -n "$PXX_VM_PTY" ]; then
      script -qc "ssh -tt $SSHO -p $PORT root@127.0.0.1 '$pre $envs /tmp/pxxbin $*'" /dev/null </dev/null | tr -d '\r' | sed 's/^\^@//'
    else
      ssh $SSHO -p "$PORT" root@127.0.0.1 "$pre $envs /tmp/pxxbin $*"
    fi ;;
  ssh)
    shift; exec ssh $SSHO -p "$PORT" root@127.0.0.1 "$@" ;;
  stop)
    ssh $SSHO -p "$PORT" root@127.0.0.1 "shutdown -p now" || true ;;
  *)
    sed -n '2,13p' "$0"; exit 2 ;;
esac
