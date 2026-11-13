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
#
# PXX_NBSD_ARCH=aarch64 selects the arm64 VM ($PXX_VM_DIR/netbsd-arm64,
# port 2229): the stock evbarm-aarch64 arm64.img as nb.qcow2, set up over its
# serial console the same way, run by qemu-system-aarch64 under TCG with the
# AAVMF firmware (slow to boot).
set -e
if [ "${PXX_NBSD_ARCH:-amd64}" = aarch64 ]; then
  VMDIR="${PXX_VM_DIR:-/data/vm}/netbsd-arm64"
  PORT="${PXX_NBSD_PORT:-2229}"
  IMG="$VMDIR/nb.qcow2"
  QEMU="qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 2048"
  FW="${PXX_AAVMF_CODE:-/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd}"
  WAIT=300
else
  VMDIR="${PXX_VM_DIR:-/data/vm}/netbsd"
  PORT="${PXX_NBSD_PORT:-2227}"
  IMG="$VMDIR/nbsd.qcow2"
  QEMU="qemu-system-x86_64 -enable-kvm -m 2048 -smp 2"
  FW="${PXX_OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}"
  WAIT=90
fi
SSHO="-q -i $VMDIR/id_vm -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=$VMDIR/known_hosts -o ConnectTimeout=5"
case "$1" in
  start)
    [ -f "$IMG" ] || { echo "no $IMG" >&2; exit 1; }
    if [ -f "$VMDIR/vm.pid" ] && kill -0 "$(cat "$VMDIR/vm.pid")" 2>/dev/null; then
      echo "already running"; exit 0
    fi
    $QEMU -display none -daemonize \
      -pidfile "$VMDIR/vm.pid" -serial file:"$VMDIR/console.log" \
      -drive if=pflash,format=raw,readonly=on,file="$FW" \
      -drive if=pflash,format=raw,file="$VMDIR/vars.fd" \
      -drive file="$IMG",if=virtio,format=qcow2 \
      -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22 -device virtio-net-pci,netdev=n0
    i=0; until ssh $SSHO -p "$PORT" root@127.0.0.1 true 2>/dev/null; do
      i=$((i+1)); [ $i -lt $WAIT ] || { echo "no ssh after $((WAIT*2))s" >&2; exit 1; }; sleep 2
    done
    # The evbarm image's root comes up noatime (not from /etc/fstab), and a
    # test that sets and reads back atime then differs from Linux.
    if [ "${PXX_NBSD_ARCH:-amd64}" = aarch64 ]; then
      ssh $SSHO -p "$PORT" root@127.0.0.1 "/sbin/mount -u -o atime /"
    fi
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
    ssh $SSHO -p "$PORT" root@127.0.0.1 "/sbin/shutdown -p now" || true ;;
  *)
    sed -n '2,18p' "$0"; exit 2 ;;
esac
