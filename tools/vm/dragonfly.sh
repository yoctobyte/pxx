#!/bin/sh
# DragonFly BSD/x86-64 test VM (feature-port-libc-family-openbsd-netbsd-minix).
#
#   tools/vm/dragonfly.sh start     boot headless (ssh on 127.0.0.1:$PXX_DFLY_PORT)
#   tools/vm/dragonfly.sh run BIN [ARGS...]   copy BIN in, run it, relay stdout/stderr/exit
#   tools/vm/dragonfly.sh ssh [CMD]  a shell (or one command) in the VM
#   tools/vm/dragonfly.sh stop
#
# The VM lives in $PXX_VM_DIR/dragonfly (default /data/vm/dragonfly):
# dfly.qcow2, id_vm (ssh key for root), known_hosts. It is the stock
# dfly-x86_64-6.4.2_REL.img (the USB image, md5 checked) as a qcow2, booted by
# SeaBIOS, set up once from its console (qemu monitor sendkey): a root key,
# console="comconsole" in /boot/loader.conf, sshd_enable and DHCP on em0 in
# /etc/rc.conf, PermitRootLogin prohibit-password, noatime dropped from the
# root line of /etc/fstab (a test reads atime back), and root's shell set to
# /bin/sh (run uses ulimit). Needs qemu-system-x86_64 with KVM. Port 2230.
set -e
VMDIR="${PXX_VM_DIR:-/data/vm}/dragonfly"
PORT="${PXX_DFLY_PORT:-2230}"
IMG="$VMDIR/dfly.qcow2"
QEMU="qemu-system-x86_64 -enable-kvm -m 2048 -smp 2"
WAIT=90
SSHO="-q -i $VMDIR/id_vm -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=$VMDIR/known_hosts -o ConnectTimeout=5"
case "$1" in
  start)
    [ -f "$IMG" ] || { echo "no $IMG" >&2; exit 1; }
    if [ -f "$VMDIR/vm.pid" ] && kill -0 "$(cat "$VMDIR/vm.pid")" 2>/dev/null; then
      echo "already running"; exit 0
    fi
    $QEMU -display none -daemonize \
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
    sed -n '2,15p' "$0"; exit 2 ;;
esac
