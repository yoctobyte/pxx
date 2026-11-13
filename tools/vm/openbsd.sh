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
#
# PXX_OBSD_ARCH=aarch64 selects the arm64 VM ($PXX_VM_DIR/openbsd-arm64,
# port 2231): installed the same way from the stock miniroot80.img (its
# install.py), run by qemu-system-aarch64 -M virt under TCG with the AAVMF
# firmware (slow to boot).
set -e
if [ "${PXX_OBSD_ARCH:-amd64}" = aarch64 ]; then
  VMDIR="${PXX_VM_DIR:-/data/vm}/openbsd-arm64"
  PORT="${PXX_OBSD_PORT:-2231}"
  FW="${PXX_AAVMF_CODE:-/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd}"
  QEMU="qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 2048
    -drive if=pflash,format=raw,readonly=on,file=$FW
    -drive if=pflash,format=raw,file=$VMDIR/vars.fd"
  WAIT=300
else
  VMDIR="${PXX_VM_DIR:-/data/vm}/openbsd"
  PORT="${PXX_OBSD_PORT:-2222}"
  QEMU="qemu-system-x86_64 -enable-kvm -m 2048 -smp 2"
  WAIT=90
fi
SSHO="-q -i $VMDIR/id_vm -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=$VMDIR/known_hosts -o ConnectTimeout=5"

case "$1" in
  start)
    [ -f "$VMDIR/obsd.qcow2" ] || { echo "no $VMDIR/obsd.qcow2" >&2; exit 1; }
    if [ -f "$VMDIR/vm.pid" ] && kill -0 "$(cat "$VMDIR/vm.pid")" 2>/dev/null; then
      echo "already running"; exit 0
    fi
    $QEMU -display none -daemonize \
      -pidfile "$VMDIR/vm.pid" -serial file:"$VMDIR/console.log" \
      -drive file="$VMDIR/obsd.qcow2",if=virtio,format=qcow2 \
      -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22 -device virtio-net-pci,netdev=n0
    i=0; until ssh $SSHO -p "$PORT" root@127.0.0.1 true 2>/dev/null; do
      i=$((i+1)); [ $i -lt $WAIT ] || { echo "no ssh after $((WAIT*2))s" >&2; exit 1; }; sleep 2
    done
    echo "up on port $PORT" ;;
  run)
    shift; b="$1"; shift
    # One retry: under TCG the arm64 VM now and then drops a connection
    # before the transfer (nothing in authlog); the test is not at fault.
    scp $SSHO -P "$PORT" "$b" root@127.0.0.1:/tmp/pxxbin.new >/dev/null 2>&1 ||
      { sleep 3; scp $SSHO -P "$PORT" "$b" root@127.0.0.1:/tmp/pxxbin.new >/dev/null; } || exit 125
    # PXX_TEST_* variables are forwarded, as tools/vm/freebsd.sh does.
    envs=$(env | grep '^PXX_TEST_[A-Za-z0-9_]*=' | sed "s/'/'\\\\''/g; s/=\(.*\)/='\1'/" | tr '\n' ' ')
    # Linux's default 8 MB stack, so a stack-overflow test takes the same path.
    pre="mv -f /tmp/pxxbin.new /tmp/pxxbin && chmod +x /tmp/pxxbin && cd /tmp && ulimit -s 8192 &&"
    # PXX_VM_PTY=1 runs it on a real tty: ssh -tt inside a local script(1).
    # OpenBSD's own script(1) with no tty on stdin hands the pty all-zero
    # termios, which is not what a terminal program meets. CRs and the NUL
    # the outer pty echoes (shown as ^@) are stripped.
    if [ -n "$PXX_VM_PTY" ]; then
      script -qc "ssh -tt $SSHO -p $PORT root@127.0.0.1 '$pre $envs /tmp/pxxbin $*'" /dev/null </dev/null | tr -d '\r' | sed 's/^\^@//'
    else
      ssh $SSHO -p "$PORT" root@127.0.0.1 "$pre $envs /tmp/pxxbin $*"
    fi ;;
  ssh)
    shift; exec ssh $SSHO -p "$PORT" root@127.0.0.1 "$@" ;;
  stop)
    ssh $SSHO -p "$PORT" root@127.0.0.1 "halt -p" || true ;;
  *)
    sed -n '2,17p' "$0"; exit 2 ;;
esac
