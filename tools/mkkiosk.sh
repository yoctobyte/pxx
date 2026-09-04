#!/usr/bin/env bash
# Build and boot the pxx kiosk image: a Linux kernel + an initramfs carrying
# busybox, the self-hosting compiler, its sources, and a kiosk app.
#
# Rung 3 of feature-busybox-kiosk-selfhosting-target. Measured 2026-08-30:
# builds in seconds, boots in ~2s under KVM, and reaches a SELF-HOST FIXEDPOINT
# INSIDE THE VM in ~34s.
#
# WHAT RUNG 3 STILL OWED after that, and what --busybox/--cases now pay: the
# image above boots DEBIAN'S busybox as PID 1 (the `cp /usr/bin/busybox` below).
# The rung asks for OURS. `--busybox=<binary>` installs a pxx-built busybox as
# /bin/busybox, and `--cases=<busybox_diff work dir>` runs that harness's own
# case list INSIDE the guest and diffs the transcript against the host oracle.
# Met 2026-09-04: 258 applets, 621 cases, byte-identical, with sha256(/proc/1/exe)
# equal to the binary we shipped.
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
#         tools/mkkiosk.sh --busybox=<binary> [--cases=<busybox_diff work dir>]
#
# PXX= overrides the compiler used for the kiosk app (Track B builds with
# $(PXX_STABLE) and does not rebuild the compiler).
set -euo pipefail

WORK="${KIOSK_WORK:-/tmp/pxx-kiosk}"
ALPINE="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases"
ARCH=x86_64; SELFHOST=0; INTERACTIVE=0; BUSYBOX=""; CASES=""
PXX="${PXX:-compiler/pascal26}"
for a in "$@"; do
  case "$a" in
    --arch=*)      ARCH="${a#*=}" ;;
    --busybox=*)   BUSYBOX="${a#*=}" ;;
    --cases=*)     CASES="${a#*=}" ;;
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
[ -x "$PXX" ] || { echo "no compiler at $PXX (build one, or set PXX=)" >&2; exit 1; }
if [ -n "$CASES" ] && [ -z "$BUSYBOX" ]; then
  echo "--cases needs --busybox: the case list exists to test OUR busybox" >&2; exit 2; fi
if [ -n "$BUSYBOX" ] && [ ! -x "$BUSYBOX" ]; then
  echo "--busybox: $BUSYBOX is not executable" >&2; exit 2; fi
if [ -n "$BUSYBOX" ] && [ "$ARCH" != x86_64 ]; then
  echo "--busybox is x86_64-only for now" >&2; exit 2; fi
if [ -n "$CASES" ] && [ ! -f "$CASES/oracle_gcc.out" ]; then
  echo "--cases: no oracle_gcc.out in $CASES (pass busybox_diff.sh --keep's work dir)" >&2; exit 2; fi
BBDIFF=tools/busybox_diff.sh

mkdir -p "$WORK"
[ -f "$WORK/vmlinuz-virt" ] || { echo "fetching $ARCH kernel..."; curl -sL -o "$WORK/vmlinuz-virt" "$ALPINE/$ARCH/netboot/vmlinuz-virt"; }

R="$WORK/root"; rm -rf "$R"; mkdir -p "$R"
if [ "$ARCH" = x86_64 ]; then
  mkdir -p "$R"/{bin,proc,sys,dev,tmp,src,opt/pxx/compiler,opt/pxx/lib}
  if [ -n "$BUSYBOX" ]; then
    # OUR busybox as the userland, which is what rung 3 is actually about.
    # Three things the host's busybox gave for free and this one does not:
    #
    #  * IT IS DYNAMIC. `gcc -o out obj/*.o` links dynamically by default and
    #    -static is not available: errno is a non-TLS weak .bss object in every
    #    pxx object and ld refuses it against libc.a's TLS one
    #    (bug-a-errno-is-one-global-across-all-threads-...). So carry the loader
    #    and every library ldd names.
    #  * NO --install. CONFIG_FEATURE_INSTALLER is off, so `busybox --install -s`
    #    answers "applet not found"; the symlinks are made here instead.
    #  * NO `sh` AND NO `[`. Both are real applets whose Config.in knob is
    #    spelled unlike the applet name (SH_IS_ASH, TEST1), so an applet list
    #    built from names cannot select them. `ash` IS present and is what init
    #    uses below; `[` gets the shim further down, because a userland without
    #    it cannot run an ordinary shell script.
    cp "$BUSYBOX" "$R/bin/busybox"; chmod +x "$R/bin/busybox"
    for a in $("$R/bin/busybox" --list); do
      [ "$a" = busybox ] || ln -sf busybox "$R/bin/$a"
    done
    for lib in $(ldd "$BUSYBOX" | awk '{for(i=1;i<=NF;i++) if($i ~ /^\//) print $i}'); do
      mkdir -p "$R$(dirname "$lib")"; cp -L "$lib" "$R$lib"
    done
    if "$R/bin/busybox" --list | grep -qx '\['; then :; else
      cat > "$R/bin/[" <<'SHIM'
#!/bin/busybox ash
n=$#; i=0
for a in "$@"; do i=$((i+1)); case $i in $n) ;; *) set -- "$@" "$a";; esac; done
shift $n
exec /bin/test "$@"
SHIM
      chmod +x "$R/bin/["
    fi
  else
    # the host's own busybox is static x86-64 -- no rootfs needed at all
    cp /usr/bin/busybox "$R/bin/"
  fi
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
  cp "$PXX" "$R/opt/pxx/compiler/pascal26"
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
"$PXX" $TGT "$R/src/kiosk.pas" "$R/bin/kiosk" >/dev/null

# ---- the in-guest case list (--cases) ---------------------------------------
# Rung 3's proof obligation is not "it boots": it is the SAME case list
# tools/busybox_diff.sh runs on the host, executed inside the guest, and the
# transcript COMPARED rather than eyeballed. Three things make that comparable:
#
#  * THE CASES ARE EXTRACTED FROM busybox_diff.sh, not reimplemented. A second
#    copy of the recipe is how the two drift apart, and a drifted case list
#    diffs as a busybox defect.
#  * THE INPUTS KEEP THEIR HOST ABSOLUTE PATH. Error messages name the file
#    ("cat: can't open '/tmp/.../a.txt'"), so the guest has to find them at the
#    identical path or 34 cases diff for a reason that is not a defect. This is
#    also why the proof init does NOT mount a tmpfs over /tmp: that path starts
#    /tmp/, and mounting over it hid every input.
#  * THE APPLET LIST INCLUDES `busybox` ITSELF. `--list` does not print the
#    multiplexer's own name; busybox_diff.sh's list does, and the two cases it
#    contributes are the ones that print the banner. Deriving the guest list
#    from `--list` alone silently ran 619 cases against a 621-case oracle.
if [ -n "$CASES" ]; then
  [ -f "$BBDIFF" ] || { echo "$BBDIFF is missing -- the case list comes from it" >&2; exit 1; }
  D="$CASES/data"
  mkdir -p "$R$D" "$R/bb"
  for f in a.txt b.txt bin.dat empty.txt nonl.txt; do cp "$D/$f" "$R$D/$f"; done
  # install_bin's layout: the real binary plus one symlink per applet. A hard
  # link, so cpio stores the (large) binary once.
  ln -f "$R/bin/busybox" "$R/bb/busybox" 2>/dev/null || cp "$R/bin/busybox" "$R/bb/busybox"
  APPLETS="$( { "$R/bin/busybox" --list; echo busybox; } | sort | tr '\n' ' ')"
  for a in $APPLETS; do [ "$a" = busybox ] || ln -sf busybox "$R/bb/$a"; done
  extract_fn() {   # $1 = function name, from its header to the first line that is just `}`
    awk -v fn="$1" '$0 ~ "^"fn"\\(\\) \\{" {p=1} p {print} p && /^}$/ {exit}' "$BBDIFF"
  }
  CASEFNS="run_one has_applet run_cat_cases run_dispatch_cases run_echo_cases
           write_ash_scripts run_ash_cases run_coreutils_cases run_cases"
  {
    echo '#!/bin/busybox ash'
    printf 'APPLETS="%s"\n' "$APPLETS"
    printf 'NAPPLETS=%d\n' "$(printf '%s\n' $APPLETS | wc -l)"
    printf 'D=%s\n' "$D"
    for f in $CASEFNS; do extract_fn "$f"; echo; done
    echo 'run_cases "" /bb'
  } > "$R/runcases.sh"
  chmod +x "$R/runcases.sh"
  # Positive control on the EXTRACTOR: an awk pattern that silently matches
  # nothing produces a script that runs zero cases and diffs as a total failure
  # of the subject, which is the wrong conclusion to hand anyone.
  for f in $CASEFNS; do
    grep -q "^$f() {" "$R/runcases.sh" || { echo "extraction lost $f from $BBDIFF" >&2; exit 1; }
  done
  echo "cases: $(printf '%s\n' $APPLETS | wc -l) applets, extracted from $BBDIFF ($(sha256sum "$BBDIFF" | cut -c1-12))"
fi

# `sh` is not an applet in a pxx-built busybox (SH_IS_ASH), and --install needs
# CONFIG_FEATURE_INSTALLER, which is also off; the symlinks were made above.
SHELLAPP=sh; [ -n "$BUSYBOX" ] && SHELLAPP=ash
{
printf '#!/bin/busybox %s\n' "$SHELLAPP"
[ -n "$BUSYBOX" ] || printf '/bin/busybox --install -s /bin\n'
printf 'mount -t proc none /proc; mount -t sysfs none /sys\n'
printf 'mount -t devtmpfs none /dev 2>/dev/null\n'
if [ -n "$CASES" ]; then
cat <<'PROOF'
export PATH=/bin
echo "PID1-EXE=$(sha256sum /proc/1/exe | cut -d' ' -f1)"
echo "BIN-BUSYBOX=$(sha256sum /bin/busybox | cut -d' ' -f1)"
/bin/busybox ash /runcases.sh > /guest.out 2>&1
echo "GUEST-CASES-BEGIN"
base64 < /guest.out
echo "GUEST-CASES-END"
echo "GUEST-BYTES=$(wc -c < /guest.out)"
poweroff -f
PROOF
else
printf 'mount -t tmpfs none /tmp\n'
cat <<'INIT'
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
fi
} > "$R/init"
# the trailing interactive shell, in the dialect this image actually has
sed -i "s|^  /bin/kiosk; exec sh\$|  /bin/kiosk; exec $SHELLAPP|" "$R/init"
chmod +x "$R/init"
[ -f "$R/bin/kiosk" ] && chmod +x "$R/bin/kiosk"
[ -f "$R/opt/pxx/compiler/pascal26" ] && chmod +x "$R/opt/pxx/compiler/pascal26"
( cd "$R" && find . | cpio -o -H newc 2>/dev/null | gzip -9 ) > "$WORK/initramfs.gz"
echo "image: kernel $(du -h "$WORK/vmlinuz-virt"|cut -f1) + initramfs $(du -h "$WORK/initramfs.gz"|cut -f1)"

APPEND="console=$CONSOLE quiet"; [ "$INTERACTIVE" = 1 ] || APPEND="$APPEND KIOSK_AUTO=1"
# KVM only when the guest arch IS the host arch; aarch64 here is real emulation
KVM=""; [ "$ARCH" = x86_64 ] && [ -r /dev/kvm ] && KVM="-enable-kvm"
# A pxx busybox image carries ~170 MB of userland (N objects, N copies of crtl --
# feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-...), which is
# unpacked into a ramfs, so the 2048 that suits a 15 MB image is not enough.
MEM=2048; [ -n "$BUSYBOX" ] && MEM=3072

if [ -z "$CASES" ]; then
  exec "$QEMU" $MACH $KVM -m $MEM -smp 2 \
    -kernel "$WORK/vmlinuz-virt" -initrd "$WORK/initramfs.gz" \
    -append "$APPEND" -nographic -no-reboot
fi

# ---- --cases: boot, then COMPARE --------------------------------------------
LOG="$WORK/guest.log"; OUT="$WORK/guest.out"; ORACLE="$CASES/oracle_gcc.out"
"$QEMU" $MACH $KVM -m $MEM -smp 2 \
  -kernel "$WORK/vmlinuz-virt" -initrd "$WORK/initramfs.gz" \
  -append "console=$CONSOLE quiet" -nographic -no-reboot > "$LOG" 2>&1

# The transcript comes back base64 because one case cats 4 KB of /dev/urandom
# and a serial console is not a binary-safe channel. `tr -d '\r'` because it is
# a TTY and the guest's newlines arrive as CRLF.
grep -aq 'GUEST-BYTES=' "$LOG" \
  || { echo "the guest never finished the case list -- see $LOG" >&2; exit 1; }
sed -n '/GUEST-CASES-BEGIN/,/GUEST-CASES-END/p' "$LOG" | sed '1d;$d' | tr -d '\r' \
  | base64 -d > "$OUT"

# PID 1 IS OUR BINARY, asserted rather than asserted-in-prose: the guest hashed
# /proc/1/exe, and a shell script as init means PID 1's exe is the interpreter,
# which is the busybox we shipped.
# NOT an anchored grep: the kernel's console-clear escape lands on the same
# line, so `^PID1-EXE=` matches nothing -- and under `set -o pipefail` that
# turned a missing marker into a SILENT exit 1 with no diagnostic at all.
gsha="$(tr -d '\r' < "$LOG" | sed -n 's/.*PID1-EXE=\([0-9a-f]\{64\}\).*/\1/p' | head -1)"
hsha="$(sha256sum "$BUSYBOX" | cut -d' ' -f1)"
[ "$gsha" = "$hsha" ] \
  || { echo "PID 1 is NOT the binary we shipped: guest $gsha, host $hsha" >&2; exit 1; }
echo "  PID 1   sha256 $(echo "$gsha" | cut -c1-12) == the busybox we built"

count_cases() { grep -a '^### ' "$1" | grep -avc '^### exit=' || true; }
nor="$(count_cases "$ORACLE")"; ngu="$(count_cases "$OUT")"
[ "$nor" -gt 0 ] \
  || { echo "the oracle transcript holds no cases -- an identical result over nothing is not a result" >&2; exit 1; }
[ "$ngu" = "$nor" ] \
  || { echo "the guest ran $ngu cases against a $nor-case oracle -- not the same comparison" >&2; exit 1; }

# POSITIVE CONTROL, because a comparison that cannot fail prints PASS: flip one
# byte of the guest transcript and require cmp to reject it. Costs nothing and
# is the only thing standing between "byte-identical" and "cmp was given two
# names for one file".
CTL="$WORK/guest.ctl"
{ head -c 1 "$OUT" | tr -c '\0' 'X'; tail -c +2 "$OUT"; } > "$CTL"
if cmp -s "$ORACLE" "$CTL"; then
  echo "the byte comparison accepted a mutated transcript -- it proves nothing" >&2; exit 1
fi
echo "  CONTROL cmp rejects a one-byte mutation of the same transcript"

if cmp -s "$ORACLE" "$OUT"; then
  printf '  PASS    in-guest transcript byte-identical to the host gcc oracle over %d cases\n' "$nor"
  echo "KIOSK-BUSYBOX-COMPLETE"
else
  echo "  FAIL    the in-guest transcript differs from the host oracle:"
  diff -a "$ORACLE" "$OUT" | head -30
  exit 1
fi
