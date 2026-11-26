#!/bin/sh
# test.sh: PASS/FAIL for the busybox recipe, on the build host.
#
# 1. Replays the recorded recipe with onsite.sh as the target would: a PATH
#    with only sh, tar, bzcat, sed, grep and coreutils (no gcc, make,
#    binutils or python).
# 2. busybox's own testsuite (testsuite/runtest) on the on-site build and on
#    record.sh's gcc build of the same configuration. PASS needs no test
#    failing for pxx that passes for gcc.
# 3. Rainyday boots with the on-site busybox as its userland (Rainyday's
#    tools/rumpnictest.sh, with the on-site rumpnic when NODISX_WORK has one,
#    else the tree's): init's sh script, mount, ip, udhcpc and its hook
#    script, ping, wget and md5sum, all from this busybox.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/busybox/test.sh
# Needs record.sh to have run; RAINYDAY (default ~/rainyday) with a built
# kernel (KERNEL, default its kernel/build/pxx/rainyday.elf), and QEMU.
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
RD=$(cd "${RAINYDAY:-$HOME/rainyday}" && pwd)
KERNEL=${KERNEL:-$RD/kernel/build/pxx/rainyday.elf}
REF=$W/busybox-ref
R=$W/recipe/busybox
[ -f "$R/units" ] && [ -x "$REF/busybox" ] || { echo "test: no recipe; run record.sh first" >&2; exit 1; }
O=$W/busybox-onsite
rm -rf "$O"
mkdir -p "$O/bin"
for t in sh sed tar bzcat sha256sum cat cp mkdir chmod wc grep basename tail tr sort; do
  ln -s "$(command -v "$t")" "$O/bin/$t"
done
env -i PATH="$O/bin" HOME="$O" DL="$W/dl" PXX="$PXX" JOBS="${JOBS:-3}" RECIPE="$R" \
  sh "$R/onsite.sh" "$O/work"
fail=0

# 2. the testsuite, gcc and pxx, each in its own copy
[ -f "$REF/busybox.links" ] || make -C "$REF" busybox.links > /dev/null
for k in gcc pxx; do
  D=$O/ts-$k
  mkdir -p "$D"
  mkdir -p "$D/scripts"
  cp -pPR "$REF/testsuite" "$REF/.config" "$REF/busybox.links" "$D/"
  cp "$REF/scripts/echo.c" "$D/scripts/"   # runtest builds its echo helper with the host cc
  if [ $k = gcc ]; then cp "$REF/busybox" "$D/busybox"; else cp "$O/work/busybox" "$D/busybox"; fi
  ( cd "$D/testsuite" && bindir=$D srcdir=$D/testsuite timeout 1800 sh ./runtest ) > "$O/ts-$k.log" 2>&1 || true
  grep '^FAIL: ' "$O/ts-$k.log" | sort -u > "$O/ts-$k.fail" || true
  echo "testsuite $k: $(grep -c '^PASS: ' "$O/ts-$k.log") PASS, $(wc -l < "$O/ts-$k.fail") FAIL"
done
new=$(comm -23 "$O/ts-pxx.fail" "$O/ts-gcc.fail")
if [ -n "$new" ]; then
  echo "testsuite: FAIL for pxx only:"; echo "$new" | sed 's/^/  /'; fail=1
else
  echo "testsuite: no failure that gcc's build does not have"
fi

# 3. Rainyday with this busybox as its userland
RN=$W/rumpnic-onsite/work/rumpnic
[ -x "$RN" ] || RN=$RD/drivers/build/rumpnic
timeout 300 "$RD/tools/rumpnictest.sh" "$KERNEL" "$O/work/busybox" "$RN" > "$O/boot.log" 2>&1 || true
if grep -q 'rumpnictest: PASS' "$O/boot.log"; then
  echo "Rainyday boots with it (DHCP, ping, fetch through rumpnic $(basename "$(dirname "$(dirname "$RN")")")): PASS"
else
  echo "Rainyday with this busybox: FAIL"; tail -15 "$O/boot.log"; fail=1
fi
if [ "$fail" = 0 ]; then echo "busybox recipe: PASS"; else echo "busybox recipe: FAIL"; exit 1; fi
