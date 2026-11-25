#!/bin/sh
# test.sh: PASS/FAIL for the mksh recipe, on the build host.
#
# Replays the recorded recipe with onsite.sh as the target would, then runs
# mksh's own regression suite (check.t, ~570 tests, through check.pl) on the
# pxx build AND on the gcc reference build record.sh made, and compares the
# two failure lists. Some tests fail on both in a non-interactive environment
# (no tty, history); PASS means the pxx build fails nothing the gcc build
# passes.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/mksh/test.sh
# Needs record.sh to have run, and perl (host only).
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
R=$W/recipe/mksh
[ -f "$R/units" ] || { echo "test: no recipe; run record.sh first" >&2; exit 1; }
O=$W/mksh-onsite
rm -rf "$O"
DL=$W/dl PXX=$PXX RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root"
B=$W/mksh-ref/build
( cd "$B" && timeout 900 ./mksh test.sh -Q ) > "$O/check-gcc.log" 2>&1 || true
( cd "$B" && timeout 1500 ./mksh test.sh -Q -p "$O/work/build/mksh" ) > "$O/check-pxx.log" 2>&1 || true
grep -a '^FAIL' "$O/check-gcc.log" | sort > "$O/fail-gcc.txt" || true
grep -a '^FAIL' "$O/check-pxx.log" | sort > "$O/fail-pxx.txt" || true
grep -a 'Total passed' "$O/check-gcc.log" "$O/check-pxx.log" | sed "s|$O/||"
only=$(comm -13 "$O/fail-gcc.txt" "$O/fail-pxx.txt" | sed 's/.*check\.t://')
npass=$(grep -a 'Total passed' "$O/check-pxx.log" | grep -oE '[0-9]+' || echo 0)
if [ -z "$only" ] && [ "$npass" -gt 400 ]; then
  echo "mksh recipe: PASS (fails nothing the gcc build passes)"
else
  echo "pxx-only failures: $only"
  echo "mksh recipe: FAIL"
  exit 1
fi
