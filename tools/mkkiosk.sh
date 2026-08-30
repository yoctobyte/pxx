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
KURL="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/netboot/vmlinuz-virt"
SELFHOST=0; INTERACTIVE=0
for a in "$@"; do
  case "$a" in
    --selfhost)    SELFHOST=1 ;;
    --interactive) INTERACTIVE=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

command -v qemu-system-x86_64 >/dev/null || { echo "qemu-system-x86_64 missing" >&2; exit 1; }
[ -x compiler/pascal26 ] || { echo "build the compiler first: make compiler/pascal26" >&2; exit 1; }

mkdir -p "$WORK"
[ -f "$WORK/vmlinuz-virt" ] || { echo "fetching kernel..."; curl -sL -o "$WORK/vmlinuz-virt" "$KURL"; }

R="$WORK/root"; rm -rf "$R"; mkdir -p "$R"/{bin,proc,sys,dev,tmp,src,opt/pxx/compiler,opt/pxx/lib}
cp /usr/bin/busybox "$R/bin/"          # static; the userland
cp compiler/pascal26 "$R/opt/pxx/compiler/"
cp -r compiler/builtin "$R/opt/pxx/compiler/"
cp -r lib/rtl "$R/opt/pxx/lib/"
cp -r lib/asmcore "$R/opt/pxx/lib/"    # Makefile:22 names the full unit payload
[ "$SELFHOST" = 1 ] && cp compiler/*.pas compiler/*.inc "$R/opt/pxx/compiler/"

# The compiler resolves units RELATIVE TO ITS OWN BINARY (<bindir>/../lib/rtl),
# so every stage must live beside the sources. A stage built into /tmp looks for
# /tmp/../lib/rtl and fails -- measured, not guessed.
cp examples/kiosk.pas "$R/src/kiosk.pas" 2>/dev/null || true
compiler/pascal26 "$R/src/kiosk.pas" "$R/bin/kiosk" >/dev/null

cat > "$R/init" <<'INIT'
#!/bin/busybox sh
/bin/busybox --install -s /bin
mount -t proc none /proc; mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null; mount -t tmpfs none /tmp
PXX=/opt/pxx/compiler/pascal26
echo; echo "=== pxx kiosk: kernel $(uname -r) on $(uname -m) ==="
printf 'program hello;\nbegin WriteLn(%s); end.\n' "'compiled inside the vm'" > /src/hello.pas
$PXX /src/hello.pas /bin/hello && /bin/hello || echo "IN-VM COMPILE FAILED"
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
chmod +x "$R/init" "$R/bin/"* "$R/opt/pxx/compiler/pascal26"
( cd "$R" && find . | cpio -o -H newc 2>/dev/null | gzip -9 ) > "$WORK/initramfs.gz"
echo "image: kernel $(du -h "$WORK/vmlinuz-virt"|cut -f1) + initramfs $(du -h "$WORK/initramfs.gz"|cut -f1)"

APPEND="console=ttyS0 quiet"; [ "$INTERACTIVE" = 1 ] || APPEND="$APPEND KIOSK_AUTO=1"
KVM=""; [ -r /dev/kvm ] && KVM="-enable-kvm"
exec qemu-system-x86_64 $KVM -m 2048 -smp 2 \
  -kernel "$WORK/vmlinuz-virt" -initrd "$WORK/initramfs.gz" \
  -append "$APPEND" -nographic -no-reboot
