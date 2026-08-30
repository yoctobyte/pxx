#!/usr/bin/env bash
# Build and boot the pxx kiosk image: a Linux kernel + an initramfs carrying
# busybox, the self-hosting compiler, its sources, and a kiosk app.
#
# Rung 3 of feature-busybox-kiosk-selfhosting-target. Measured 2026-08-30:
# builds in seconds, boots in ~2s under KVM, and reaches a SELF-HOST FIXEDPOINT
# INSIDE THE VM in ~34s.
#
# WHY NO DISTRO ROOTFS, and it is a measurement not a preference: pascal26 and
# everything it emits are STATICALLY linked (`file compiler/pascal26` ->
# "statically linked"). So the image needs no libc, no dynamic loader and no
# userland -- kernel + initramfs of static binaries is complete. That is what
# makes it 15 MB and 2 seconds instead of a distro image.
#
# WHY A FETCHED KERNEL: building one is hours; this is 12 MB and 1 second. The
# host's own /boot/vmlinuz is 0600 root-only, so the zero-download path needs
# sudo and is not worth it. Re-decide per target if a cross image needs one.
#
# Usage:  tools/mkkiosk.sh [--selfhost] [--interactive]
set -euo pipefail

WORK="${KIOSK_WORK:-/tmp/pxx-kiosk}"
ALPINE="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases"
ARCH=x86_64; SELFHOST=0; INTERACTIVE=0
for a in "$@"; do
  case "$a" in
    --arch=*)      ARCH="${a#*=}" ;;
    --selfhost)    SELFHOST=1 ;;
    --interactive) INTERACTIVE=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done
case "$ARCH" in
  x86_64)  QEMU=qemu-system-x86_64; MACH=""; CONSOLE=ttyS0 ;;
  aarch64) QEMU=qemu-system-aarch64; MACH="-machine virt -cpu cortex-a57"; CONSOLE=ttyAMA0
           # aarch64 CANNOT carry the compiler yet -- see --selfhost note below
           SELFHOST=0 ;;
  *) echo "unsupported --arch: $ARCH (x86_64|aarch64)" >&2; exit 2 ;;
esac
WORK="$WORK-$ARCH"

command -v "$QEMU" >/dev/null || { echo "$QEMU missing" >&2; exit 1; }
[ -x compiler/pascal26 ] || { echo "build the compiler first: make compiler/pascal26" >&2; exit 1; }

mkdir -p "$WORK"
[ -f "$WORK/vmlinuz-virt" ] || { echo "fetching $ARCH kernel..."; curl -sL -o "$WORK/vmlinuz-virt" "$ALPINE/$ARCH/netboot/vmlinuz-virt"; }

R="$WORK/root"; rm -rf "$R"; mkdir -p "$R"
if [ "$ARCH" = x86_64 ]; then
  # the host's own busybox is static x86-64 -- no rootfs needed at all
  mkdir -p "$R"/{bin,proc,sys,dev,tmp,src,opt/pxx/compiler,opt/pxx/lib}
  cp /usr/bin/busybox "$R/bin/"
else
  # Alpine's aarch64 busybox is musl-DYNAMIC, so it needs its loader and libc.
  # The minirootfs (3.8 MB) supplies both. Our own binaries stay static and
  # need none of it -- the rootfs is here for busybox, not for us.
  MINI="$WORK/minirootfs.tar.gz"
  [ -f "$MINI" ] || curl -sL -o "$MINI" "$ALPINE/$ARCH/alpine-minirootfs-3.21.0-$ARCH.tar.gz"
  tar xzf "$MINI" -C "$R"
  mkdir -p "$R"/{proc,sys,dev,tmp,src,opt/pxx/compiler,opt/pxx/lib}
fi
if [ "$ARCH" = x86_64 ]; then
  cp compiler/pascal26 "$R/opt/pxx/compiler/"
  cp -r compiler/builtin "$R/opt/pxx/compiler/"
  cp -r lib/rtl "$R/opt/pxx/lib/"
  cp -r lib/asmcore "$R/opt/pxx/lib/"  # Makefile:22 names the full unit payload
  [ "$SELFHOST" = 1 ] && cp compiler/*.pas compiler/*.inc "$R/opt/pxx/compiler/"
fi
# NO COMPILER IN THE aarch64 IMAGE, and it is a measured gap rather than a
# choice: `pascal26 --target=aarch64 compiler/compiler.pas` fails with
#   cpreproc.inc:2105  target aarch64: LoadFile expects a managed-string destination
# so there is no aarch64 pascal26 to ship. Ordinary programs cross-build and run
# fine -- that is what the kiosk app in this image is. See
# bug-a-the-compiler-cannot-cross-build-itself-for-aarch64.

# The compiler resolves units RELATIVE TO ITS OWN BINARY (<bindir>/../lib/rtl),
# so every stage must live beside the sources. A stage built into /tmp looks for
# /tmp/../lib/rtl and fails -- measured, not guessed.
cp examples/kiosk.pas "$R/src/kiosk.pas" 2>/dev/null || true
TGT=""; [ "$ARCH" = x86_64 ] || TGT="--target=$ARCH"
compiler/pascal26 $TGT "$R/src/kiosk.pas" "$R/bin/kiosk" >/dev/null

cat > "$R/init" <<'INIT'
#!/bin/busybox sh
/bin/busybox --install -s /bin
mount -t proc none /proc; mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null; mount -t tmpfs none /tmp
PXX=/opt/pxx/compiler/pascal26
echo; echo "=== pxx kiosk: kernel $(uname -r) on $(uname -m) ==="
if [ -x "$PXX" ]; then
  printf 'program hello;\nbegin WriteLn(%s); end.\n' "'compiled inside the vm'" > /src/hello.pas
  $PXX /src/hello.pas /bin/hello && /bin/hello || echo "IN-VM COMPILE FAILED"
else
  echo "(no compiler in this image: it cannot cross-build itself for this arch yet"
  echo " -- bug-a-the-compiler-cannot-cross-build-itself-for-aarch64. The kiosk"
  echo " app below IS pxx-cross-compiled for $(uname -m) and is the real claim.)"
fi
if [ -f /opt/pxx/compiler/compiler.pas ]; then
  echo "--- self-host inside the vm ---"
  cd /opt/pxx/compiler
  if $PXX compiler.pas ./pascal26.stage1 && ./pascal26.stage1 compiler.pas ./pascal26.stage2; then
    cmp -s ./pascal26.stage1 ./pascal26.stage2 \
      && echo "SELF-HOST FIXEDPOINT INSIDE THE VM: stage1 == stage2" \
      || echo "NO FIXEDPOINT: stage1 != stage2"
  else echo "SELF-HOST FAILED"; fi
fi
echo "--- kiosk ---"
if [ "${KIOSK_AUTO:-0}" = "1" ]; then
  printf 'about\nsum 100\nprimes 1000\nhalt\n' | /bin/kiosk; poweroff -f
else
  /bin/kiosk; exec sh
fi
INIT
chmod +x "$R/init" "$R/bin/kiosk"
[ -f "$R/opt/pxx/compiler/pascal26" ] && chmod +x "$R/opt/pxx/compiler/pascal26"
( cd "$R" && find . | cpio -o -H newc 2>/dev/null | gzip -9 ) > "$WORK/initramfs.gz"
echo "image: kernel $(du -h "$WORK/vmlinuz-virt"|cut -f1) + initramfs $(du -h "$WORK/initramfs.gz"|cut -f1)"

APPEND="console=$CONSOLE quiet"; [ "$INTERACTIVE" = 1 ] || APPEND="$APPEND KIOSK_AUTO=1"
# KVM only when the guest arch IS the host arch; aarch64 here is real emulation
KVM=""; [ "$ARCH" = x86_64 ] && [ -r /dev/kvm ] && KVM="-enable-kvm"
exec "$QEMU" $MACH $KVM -m 2048 -smp 2 \
  -kernel "$WORK/vmlinuz-virt" -initrd "$WORK/initramfs.gz" \
  -append "$APPEND" -nographic -no-reboot
