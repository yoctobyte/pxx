#!/bin/sh
# FreeBSD test VM for --os=freebsd (feature-port-freebsd-native).
# PXX_FBSD_ARCH=aarch64 selects the arm64 VM (--os=freebsd --target=aarch64):
# its own image under $PXX_VM_DIR/freebsd-arm64, port 2228, qemu-system-aarch64
# under TCG with the AAVMF firmware (slow to boot, a few minutes).
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
REL=15.1-RELEASE
if [ "${PXX_FBSD_ARCH:-amd64}" = aarch64 ]; then
  VMDIR="${PXX_VM_DIR:-/data/vm}/freebsd-arm64"
  PORT="${PXX_FBSD_PORT:-2228}"
  IMG=FreeBSD-$REL-arm64-aarch64-BASIC-CLOUDINIT-ufs.qcow2
  URL=https://download.freebsd.org/releases/VM-IMAGES/$REL/aarch64/Latest
  QEMU="qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 4 -m 2048
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd
    -drive if=pflash,format=raw,file=$VMDIR/vars.fd"
else
  VMDIR="${PXX_VM_DIR:-/data/vm}/freebsd"
  PORT="${PXX_FBSD_PORT:-2223}"
  IMG=FreeBSD-$REL-amd64-BASIC-CLOUDINIT-ufs.qcow2
  URL=https://download.freebsd.org/releases/VM-IMAGES/$REL/amd64/Latest
  QEMU="qemu-system-x86_64 -enable-kvm -m 2048 -smp 2"
fi
export QEMU
SSHO="-q -i $VMDIR/id_vm -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=$VMDIR/known_hosts -o ConnectTimeout=5"

case "$1" in
fetch)
  mkdir -p "$VMDIR"; cd "$VMDIR"
  [ -f fbsd.qcow2 ] && { echo "already have $VMDIR/fbsd.qcow2"; exit 0; }
  curl -sSfO "$URL/$IMG.xz"; curl -sSf "$URL/CHECKSUM.SHA256" -o CHECKSUM.SHA256
  want=$(grep "($IMG.xz)" CHECKSUM.SHA256 | grep -o '[0-9a-f]\{64\}')
  [ "$(sha256sum "$IMG.xz" | cut -d' ' -f1)" = "$want" ] || { echo "checksum mismatch"; exit 1; }
  unxz "$IMG.xz"; mv "$IMG" fbsd.qcow2; qemu-img resize -q fbsd.qcow2 20G
  [ "${PXX_FBSD_ARCH:-amd64}" = aarch64 ] && cp /usr/share/AAVMF/AAVMF_VARS.fd vars.fd
  [ -f id_vm ] || ssh-keygen -q -t ed25519 -N "" -C pxx-vm -f id_vm
  # The image's root has no console password; install the key over serial
  # (the cloud-init seed route did not take on 15.1) and allow key-only root.
  python3 "$(dirname "$0")/fbsd_setup.py" "$VMDIR"
  ;;
start)
  cd "$VMDIR"
  [ -f vm.pid ] && kill -0 "$(cat vm.pid)" 2>/dev/null && exit 0
  $QEMU -display none -daemonize \
    -pidfile vm.pid -serial file:console.log \
    -drive file=fbsd.qcow2,if=virtio,format=qcow2 \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22 -device virtio-net-pci,netdev=n0 2>/dev/null
  i=0; until ssh $SSHO -p "$PORT" root@127.0.0.1 true 2>/dev/null; do
    i=$((i+1)); [ $i -gt 200 ] && { echo "VM did not come up"; exit 1; }; sleep 3; done
  ;;
run)
  shift; bin="$1"; shift
  # Upload beside and rename over: a still-running earlier binary (a timed-out
  # test) keeps /tmp/pxxbin busy, and scp onto a busy text file fails.
  scp $SSHO -P "$PORT" "$bin" root@127.0.0.1:/tmp/pxxbin.new >/dev/null || exit 125
  # PXX_TEST_* variables are forwarded, so a test can compare env-dependent output.
  envs=$(env | grep '^PXX_TEST_[A-Za-z0-9_]*=' | sed "s/'/'\\\\''/g; s/=\(.*\)/='\1'/" | tr '\n' ' ')
  # Linux's default 8 MB stack, not FreeBSD's 512 MB: a stack-overflow test
  # then takes the same path in the same time on both kernels.
  # PXX_VM_PTY=1 runs it on a pty (script(1)), CRs and script's echoed ^D stripped.
  if [ -n "$PXX_VM_PTY" ]; then
    ssh $SSHO -p "$PORT" root@127.0.0.1 "mv -f /tmp/pxxbin.new /tmp/pxxbin && chmod +x /tmp/pxxbin && cd /tmp && ulimit -s 8192 && $envs script -q /dev/null /tmp/pxxbin $* </dev/null | tr -d '\r\010' | sed 's/^\^D//'"
  else
    ssh $SSHO -p "$PORT" root@127.0.0.1 "mv -f /tmp/pxxbin.new /tmp/pxxbin && chmod +x /tmp/pxxbin && cd /tmp && ulimit -s 8192 && $envs /tmp/pxxbin $*"
  fi
  ;;
stop)
  ssh $SSHO -p "$PORT" root@127.0.0.1 "shutdown -p now" 2>/dev/null || true
  ;;
*) sed -n '2,12p' "$0"; exit 2 ;;
esac
