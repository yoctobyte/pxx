#!/bin/sh
# Minix 3.4/i386 test VM (feature-port-libc-family-openbsd-netbsd-minix).
# There is no --os=minix yet; this VM is for that port's measurements.
#
#   tools/vm/minix.sh start     boot headless (ssh on 127.0.0.1:$PXX_MINIX_PORT)
#   tools/vm/minix.sh run BIN [ARGS...]   copy BIN in, run it, relay stdout/stderr/exit
#   tools/vm/minix.sh ssh [CMD]  a shell (or one command) in the VM
#   tools/vm/minix.sh stop
#
# The VM lives in $PXX_VM_DIR/minix (default /data/vm/minix): minix.qcow2,
# id_vm (ssh key for root), known_hosts. It is minix_R3.4.0rc6-d5e4fc0.iso
# (sha1 checked) installed with its own `setup` over the VGA console (qemu
# monitor sendkey; defaults, em0 by DHCP), then openssh-7.3.1 from pkgin, a
# root key, PermitRootLogin prohibit-password and /usr/pkg/sbin/sshd in
# /etc/rc.local. Runs under TCG: the install under KVM stalled while
# extracting the base set. Monitor socket: monitor.sock. Port 2232.
set -e
VMDIR="${PXX_VM_DIR:-/data/vm}/minix"
PORT="${PXX_MINIX_PORT:-2232}"
IMG="$VMDIR/minix.qcow2"
WAIT=150
SSHO="-q -i $VMDIR/id_vm -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=$VMDIR/known_hosts -o ConnectTimeout=20"
case "$1" in
  start)
    [ -f "$IMG" ] || { echo "no $IMG" >&2; exit 1; }
    if [ -f "$VMDIR/vm.pid" ] && kill -0 "$(cat "$VMDIR/vm.pid")" 2>/dev/null; then
      echo "already running"; exit 0
    fi
    qemu-system-i386 -m 1024 -display none -daemonize \
      -pidfile "$VMDIR/vm.pid" -serial file:"$VMDIR/console.log" \
      -monitor unix:"$VMDIR/monitor.sock",server,nowait \
      -drive file="$IMG",if=ide,format=qcow2 \
      -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22 -device e1000,netdev=n0
    i=0; until ssh $SSHO -p "$PORT" root@127.0.0.1 true 2>/dev/null; do
      i=$((i+1)); [ $i -lt $WAIT ] || { echo "no ssh after $((WAIT*2))s" >&2; exit 1; }; sleep 2
    done
    echo "up on port $PORT" ;;
  run)
    shift; b="$1"; shift
    scp $SSHO -P "$PORT" "$b" root@127.0.0.1:/tmp/pxxbin.new >/dev/null || exit 125
    ssh $SSHO -p "$PORT" root@127.0.0.1 "mv -f /tmp/pxxbin.new /tmp/pxxbin && chmod +x /tmp/pxxbin && cd /tmp && /tmp/pxxbin $*" ;;
  ssh)
    shift; exec ssh $SSHO -p "$PORT" root@127.0.0.1 "$@" ;;
  stop)
    ssh $SSHO -p "$PORT" root@127.0.0.1 "shutdown -h now" || true ;;
  *)
    sed -n '2,16p' "$0"; exit 2 ;;
esac
