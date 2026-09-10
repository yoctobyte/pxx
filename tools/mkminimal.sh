#!/bin/sh
# A MINIMAL BOOTABLE SYSTEM: a Linux kernel, a busybox shell, and a pxx
# compiler. Nothing else -- that "nothing else" is the specification (owner,
# 2026-09-10): "linux kernel booting, launching a shell using busybox, and a
# pxx compiler. no more no less."
#
# It is NOT tools/mkkiosk.sh. That script boots a DEMO -- it installs
# examples/kiosk.pas, compiles a hello program, and can run a self-host
# fixedpoint inside the guest, all of which are proofs ABOUT pxx. This one ships
# a system a person sits down in front of: it ends at an interactive prompt, and
# the only thing on it besides the shell is the compiler.
#
# WHY A SEPARATE SCRIPT AND NOT A FLAG ON mkkiosk.sh: the two differ in what
# goes IN the image, and a flag that removes the payload removes what the other
# script exists to prove. Keeping them apart means neither one's trimming can
# silently weaken the other's proof.
#
#   tools/mkminimal.sh [--busybox=<path>] [--iso] [--boot] [--batch]
#
#   --busybox=<path>  the busybox to ship. DEFAULT IS THE HOST'S, which is a
#                     gcc build -- fine for an image that just has to boot, and
#                     NOT the without-external-libraries proof. Pass the
#                     freestanding pxx-linked one to get that; the script says
#                     which it used, in its own output and in the image.
#   --iso             also write a BIOS+EFI hybrid ISO (qemu and VirtualBox boot
#                     the same file). Needs xorriso, mtools, grub-pc-bin and
#                     grub-efi-amd64-bin.
#   --boot            boot the result under qemu when it is built
#   --batch           with --boot: print a banner, compile and run one Pascal
#                     program, power off -- instead of waiting at a prompt. For
#                     CI and for this script's own verification, because an
#                     interactive image cannot prove itself without a human at
#                     the console.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="${PXX_MINIMAL_WORK:-/tmp/pxx-minimal}"
PXX="${PXX:-$ROOT/compiler/pascal26}"
ALPINE=https://dl-cdn.alpinelinux.org/alpine/v3.21/releases
BUSYBOX=""; ISO=0; BOOT=0; BATCH=0

while [ $# -gt 0 ]; do
  case "$1" in
    --busybox=*) BUSYBOX="${1#*=}"; shift ;;
    --iso)       ISO=1; shift ;;
    --boot)      BOOT=1; shift ;;
    --batch)     BATCH=1; shift ;;
    *) echo "mkminimal: unknown argument $1" >&2; exit 2 ;;
  esac
done

die() { echo "mkminimal: $*" >&2; exit 1; }
[ -x "$PXX" ] || die "no compiler at $PXX (build one with 'make compiler/pascal26', or set PXX=)"
if [ -n "$BUSYBOX" ]; then
  [ -x "$BUSYBOX" ] || die "--busybox: $BUSYBOX is not executable"
  BBKIND="$BUSYBOX"
else
  BUSYBOX=/usr/bin/busybox
  [ -x "$BUSYBOX" ] || die "no busybox at $BUSYBOX and none given with --busybox="
  BBKIND="$BUSYBOX (the HOST's, a gcc build -- NOT the pxx proof)"
fi

mkdir -p "$WORK"
[ -f "$WORK/vmlinuz-virt" ] || {
  echo "mkminimal: fetching the x86_64 kernel..."
  curl -sL -o "$WORK/vmlinuz-virt" "$ALPINE/x86_64/netboot/vmlinuz-virt" \
    || die "could not fetch the kernel"
}

# ---- the root ---------------------------------------------------------------
R="$WORK/root"
rm -rf "$R"
mkdir -p "$R"/bin "$R"/proc "$R"/sys "$R"/dev "$R"/tmp \
         "$R"/opt/pxx/compiler "$R"/opt/pxx/lib

cp "$BUSYBOX" "$R/bin/busybox"; chmod +x "$R/bin/busybox"
# One symlink per applet. CONFIG_FEATURE_INSTALLER is off in the builds this
# script is aimed at, so `busybox --install -s` answers "applet not found" and
# the links are made here. `sh` is NOT among them: its knob is SH_IS_ASH, which
# an applet list built from applet NAMES cannot select, so the shell is spelled
# `ash` and init below execs that. A `sh` symlink would be a file that cannot
# run -- the multiplexer dispatches on argv[0] and has no such applet.
for a in $("$R/bin/busybox" --list); do
  [ "$a" = busybox ] || ln -sf busybox "$R/bin/$a"
done
"$R/bin/busybox" --list | grep -qx ash \
  || die "this busybox has no ash applet -- there is no shell to launch"

# A DYNAMIC busybox needs its loader and libraries; a freestanding one needs
# nothing, and `ldd` is what separates them. Asking ldd rather than branching on
# which busybox was passed keeps the two cases one code path -- and the count it
# reports is the without-external-libraries claim, measured instead of asserted.
NLIB=0
if ldd "$BUSYBOX" >/dev/null 2>&1; then
  for lib in $(ldd "$BUSYBOX" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^\//) print $i}'); do
    mkdir -p "$R$(dirname "$lib")"; cp -L "$lib" "$R$lib"; NLIB=$((NLIB+1))
  done
fi

# The compiler, and exactly what it needs to compile Pascal. It resolves units
# RELATIVE TO ITS OWN BINARY (<bindir>/../lib/rtl), so this layout is not a
# preference: a compiler at /opt/pxx/compiler/ looks in /opt/pxx/lib/, and one
# dropped in /bin would look in /lib and find nothing.
cp "$PXX" "$R/opt/pxx/compiler/pascal26"
cp -r "$ROOT/compiler/builtin" "$R/opt/pxx/compiler/"
cp -r "$ROOT/lib/rtl" "$R/opt/pxx/lib/"
cp -r "$ROOT/lib/asmcore" "$R/opt/pxx/lib/"

# ---- init -------------------------------------------------------------------
# init is pid 1 and ash is the shell, so init IS an ash script ending in
# `exec ash`: one process, no getty, no login. /dev comes from devtmpfs, which
# the kernel populates itself -- there is no mdev pass and no static device
# nodes to get wrong.
{
  echo '#!/bin/busybox ash'
  cat <<'INIT'
/bin/busybox mount -t proc     proc     /proc 2>/dev/null
/bin/busybox mount -t sysfs    sysfs    /sys  2>/dev/null
/bin/busybox mount -t devtmpfs devtmpfs /dev  2>/dev/null
export PATH=/bin:/opt/pxx/compiler
export HOME=/
# PXX_HOME IS NOT BELT-AND-BRACES, IT IS LOAD-BEARING. The compiler derives its
# library roots from its own exe dir, and it derives the exe dir from argv[0] --
# so a PATH invocation, where the shell passes the bare word `pascal26', leaves
# it with no directory to work from and it falls through to the CWD-relative
# last resort. Measured 2026-09-10 in this image: the first boot printed
# "uses: unit source not found: builtinheap" with the units sitting correctly in
# /opt/pxx/compiler/builtin the whole time, because the CWD was /tmp.
# PXX_HOME=<root> makes the roots absolute: <root>/lib/rtl, <root>/compiler/builtin.
export PXX_HOME=/opt/pxx
cd /tmp
echo
echo "  pxx minimal system -- $(/bin/busybox uname -sr)"
echo "  shell:    /bin/ash (busybox)"
echo "  compiler: pascal26 at /opt/pxx/compiler"
echo
INIT
  if [ "$BATCH" = 1 ]; then
    # The image cannot prove itself at an interactive prompt, so --batch runs
    # the one thing that distinguishes this image from a kernel with a shell on
    # it: it compiles a Pascal program with the shipped compiler, and runs it.
    cat <<'BATCHRUN'
echo "program h; begin writeln('pxx compiled and ran this inside the vm'); end." > /tmp/h.pas
if pascal26 /tmp/h.pas /tmp/h >/tmp/h.log 2>&1 && /tmp/h; then
  echo "MINIMAL-IMAGE OK"
else
  echo "MINIMAL-IMAGE FAILED"; cat /tmp/h.log
fi
# sysrq, not `poweroff': poweroff is an applet, and the applet set this image
# ships is the one the pxx build was measured on -- it does not contain one.
# Reaching for it printed "poweroff: applet not found" and init then EXITED,
# which the kernel reports as "Attempted to kill init! exitcode=0x00007f00" --
# a panic whose number is the shell's 127 and which reads as a boot failure
# rather than as a missing applet. /proc/sysrq-trigger needs nothing installed.
echo o > /proc/sysrq-trigger
/bin/busybox sleep 5
BATCHRUN
  else
    cat <<'SHELL'
echo "Write a program and compile it:"
echo "    cat > h.pas        # then, ending with ctrl-D:"
echo "    program h; begin writeln('hi'); end."
echo "    pascal26 h.pas h && ./h"
echo
echo "Power off with:  echo o > /proc/sysrq-trigger"
echo
# A LOOP, NOT `exec'. init is pid 1, so a shell that exits takes init with it
# and the kernel panics with "Attempted to kill init!" -- a ctrl-D at the prompt
# should not read as a crash. Re-running it makes exiting harmless.
while :; do /bin/busybox ash; done
SHELL
  fi
} > "$R/init"
chmod +x "$R/init"

# ---- the initramfs ----------------------------------------------------------
( cd "$R" && find . | cpio -o -H newc --quiet | gzip -9 ) > "$WORK/initramfs.gz"

printf 'mkminimal: busybox   %s\n' "$BBKIND"
printf 'mkminimal: libraries %d shared library/ies copied in for it\n' "$NLIB"
printf 'mkminimal: kernel    %s bytes\n' "$(stat -c%s "$WORK/vmlinuz-virt")"
printf 'mkminimal: initramfs %s bytes\n' "$(stat -c%s "$WORK/initramfs.gz")"

# ---- the ISO ----------------------------------------------------------------
if [ "$ISO" = 1 ]; then
  for t in xorriso mformat grub-mkrescue; do
    command -v "$t" >/dev/null 2>&1 \
      || die "--iso needs $t (apt install xorriso mtools grub-pc-bin grub-efi-amd64-bin)"
  done
  # BOTH grub platforms, asserted rather than assumed. With only x86_64-efi
  # installed, grub-mkrescue SUCCEEDS and writes an EFI-only El Torito catalog;
  # the ISO then boots nothing under SeaBIOS or a default VirtualBox VM, and the
  # failure arrives from the firmware as "Could not read from CDROM (code 0009)",
  # which reads as a corrupt image rather than as a missing build dependency.
  # Measured 2026-09-10: that is exactly how the first ISO from this recipe
  # failed, and `file` called it "(bootable)" the whole time.
  for p in i386-pc x86_64-efi; do
    [ -d "/usr/lib/grub/$p" ] \
      || die "--iso needs grub's $p platform (/usr/lib/grub/$p is missing)"
  done
  I="$WORK/isoroot"
  rm -rf "$I"
  mkdir -p "$I/boot/grub"
  cp "$WORK/vmlinuz-virt" "$I/boot/vmlinuz"
  cp "$WORK/initramfs.gz" "$I/boot/initramfs.gz"
  # console=tty0 AND ttyS0: serial is what a headless qemu run can read, tty0 is
  # what a VirtualBox window shows. Naming only one produces an image that looks
  # dead in whichever hypervisor was not the one it was tested under.
  cat > "$I/boot/grub/grub.cfg" <<'CFG'
set timeout=0
set default=0
menuentry "pxx minimal system" {
    linux /boot/vmlinuz console=tty0 console=ttyS0 quiet
    initrd /boot/initramfs.gz
}
CFG
  grub-mkrescue -o "$WORK/pxx-minimal.iso" "$I" -- -volid PXXMIN \
    >"$WORK/mkrescue.log" 2>&1 \
    || { tail -5 "$WORK/mkrescue.log" >&2; die "grub-mkrescue failed -- see $WORK/mkrescue.log"; }
  # A catalog with one platform in it is the silent failure described above, so
  # the built artefact is asked what it actually contains rather than trusted.
  xorriso -indev "$WORK/pxx-minimal.iso" -report_el_torito plain 2>/dev/null \
    | grep -q 'boot img :   1  BIOS' \
    || die "the ISO has no BIOS boot image -- it would not boot SeaBIOS or VirtualBox"
  printf 'mkminimal: iso       %s bytes (BIOS+EFI hybrid) at %s\n' \
    "$(stat -c%s "$WORK/pxx-minimal.iso")" "$WORK/pxx-minimal.iso"
fi

# ---- boot -------------------------------------------------------------------
if [ "$BOOT" = 1 ]; then
  command -v qemu-system-x86_64 >/dev/null || die "--boot needs qemu-system-x86_64"
  KVM=""; [ -r /dev/kvm ] && KVM="-enable-kvm"
  if [ "$ISO" = 1 ]; then
    echo "mkminimal: booting the ISO (ctrl-a x to quit)"
    exec qemu-system-x86_64 -m 1024 $KVM -cdrom "$WORK/pxx-minimal.iso" \
         -nographic -no-reboot
  fi
  echo "mkminimal: booting kernel+initramfs (ctrl-a x to quit)"
  exec qemu-system-x86_64 -m 1024 $KVM -kernel "$WORK/vmlinuz-virt" \
       -initrd "$WORK/initramfs.gz" -append "console=ttyS0 quiet" \
       -nographic -no-reboot
fi
