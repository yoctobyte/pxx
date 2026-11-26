#!/bin/sh
# test.sh: PASS/FAIL for the GNU make recipe, on the build host.
#
# Replays the recorded recipe with onsite.sh as the target would, then:
#  1. runs GNU make's own suite (tests/run_make_tests.pl, 1422 tests in 132
#     categories) on the pxx make and on the gcc make;
#  2. builds the Rainyday kernel (TOOLCHAIN=pxx, the build Nodisx runs on
#     site) with the host's make and with the pxx make, and compares the two
#     rainyday.elf byte for byte.
# PASS is: no suite failure the gcc build does not have, and an identical
# kernel. (The gcc build fails misc/fopen-fail on this host; it is checked
# against, not assumed.)
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/make/test.sh
# Needs record.sh to have run, perl and the host's make, and ~/rainyday
# (RAINYDAY=dir to point elsewhere; it is copied, never built in place).
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
RAINYDAY=${RAINYDAY:-$HOME/rainyday}
R=$W/recipe/make
[ -f "$R/link" ] || { echo "test: no recipe; run record.sh first" >&2; exit 1; }
O=$W/make-onsite
rm -rf "$O"
DL=$W/dl PXX=$PXX JOBS=${JOBS:-3} RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root"
REF=$W/make-ref
G=$REF/make
Q=$O/work/make
fail=0

# 1. the suite, on both builds, each in its own copy of tests/
for b in gcc pxx; do
  case $b in gcc) m=$G ;; pxx) m=$Q ;; esac
  mkdir -p "$O/suite-$b"
  cp -a "$REF/tests/." "$O/suite-$b/"
  ( cd "$O/suite-$b" && perl run_make_tests.pl -srcdir "$REF" -make "$m" ) > "$O/suite-$b.log" 2>&1 || true
  # a failing test is `name ..... FAILED (n/m passed)`, or a line naming
  # its script followed by a bare `FAILED (...)`
  awk '/FAILED/ { if ($0 ~ /^FAILED/) { if (match(p, /scripts\/[^:]*/)) print substr(p, RSTART + 8, RLENGTH - 8) } else print $1 } { p = $0 }' \
    "$O/suite-$b.log" | sort > "$O/fails-$b"
  echo "make suite ($b): $(grep -E 'Tests? in [0-9]+ Categor' "$O/suite-$b.log" | tail -1 | sed 's/ *(See.*//')"
done
new=$(comm -13 "$O/fails-gcc" "$O/fails-pxx")
[ -z "$new" ] || { echo "only the pxx make fails:"; echo "$new"; fail=1; }

# 2. the Rainyday kernel, host make vs. pxx make
if [ -d "$RAINYDAY/kernel" ]; then
  for b in host pxx; do
    rm -rf "$O/rd-$b"; mkdir -p "$O/rd-$b"
    ( cd "$RAINYDAY" && tar --exclude=kernel/build -cf - kernel include ) | tar -xf - -C "$O/rd-$b"
  done
  ( cd "$O/rd-host/kernel" && make -j3 PXX="$PXX" ) > "$O/rd-host.log" 2>&1 || { echo "kernel: host make failed"; fail=1; }
  ( cd "$O/rd-pxx/kernel" && "$Q" -j3 PXX="$PXX" ) > "$O/rd-pxx.log" 2>&1 || { echo "kernel: pxx make failed"; fail=1; }
  if cmp -s "$O/rd-host/kernel/build/pxx/rainyday.elf" "$O/rd-pxx/kernel/build/pxx/rainyday.elf"; then
    echo "kernel: rainyday.elf identical ($(wc -c < "$O/rd-pxx/kernel/build/pxx/rainyday.elf") bytes)"
  else
    echo "kernel: rainyday.elf DIFFERS"; fail=1
  fi
else
  echo "kernel: $RAINYDAY/kernel not found, NOT checked"
fi
size "$Q" | sed "s|$O/work/||"
if [ "$fail" = 0 ]; then echo "make recipe: PASS"; else echo "make recipe: FAIL"; exit 1; fi
