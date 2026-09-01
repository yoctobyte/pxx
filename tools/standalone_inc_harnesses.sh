#!/bin/sh
# Compile every test harness that includes a compiler .inc DIRECTLY.
#
# WHY THIS EXISTS, and why neither of the per-fix gates can replace it.
# A handful of .inc files have TWO including configurations: compiler.pas, and a
# standalone oracle harness that MOCKS the defs.inc environment instead of
# including it. A new reference from such an .inc into defs.inc compiles fine in
# the compiler and breaks the harness -- and `make compiler/pascal26` cannot see
# it, because the fixedpoint proves the compiler reproduces ITSELF, not that a
# file it reads is still readable by anything else. CLAUDE.md states the first
# face of that caveat (a construct the compiler never WRITES); this is the
# second (a file the compiler is not the only READER of).
#
# It has now happened twice in eleven days, with different symbols:
#   2026-08-21  undefined variable (InlineAsmLineHoleN)  test_asm_emit_a64.pas
#               -- silent, because no build rule ran the harness at all
#               (chore-a-sweep-the-unwired-tests-into-the-suite wired them)
#   2026-09-01  undefined variable (DwBackHits)          test_asm_emit_x64.pas
#               -- caught by seven's full tier, 7 commits after it landed
#
# The first one is why the second was visible: wiring them into the suite moved
# the detection from "never" to "Track T, asynchronously". This moves it to the
# per-fix loop for the only diff that can cause it.
#
# Usage: tools/standalone_inc_harnesses.sh [compiler]
set -u
PXX="${1:-compiler/pascal26}"
[ -x "$PXX" ] || { echo "no compiler at $PXX"; exit 2; }
OUT="${TMPDIR:-/tmp}/incharness.$$"
mkdir -p "$OUT" || exit 2

# harness : the compiler .inc files it compiles directly
HARNESSES="test_asm_emit_a64 test_asm_emit_386 test_asm_emit_x64 \
test_asm_emit_rv32 test_asm_emit_arm32 test_rel8_guard test_x64enc"

rc=0
n=0
for h in $HARNESSES; do
  [ -f "test/$h.pas" ] || { echo "MISSING test/$h.pas"; rc=1; continue; }
  n=$((n + 1))
  if ! "$PXX" -O2 "test/$h.pas" "$OUT/$h" > "$OUT/$h.log" 2>&1; then
    echo "FAIL  $h"
    sed -n '1,4p' "$OUT/$h.log" | sed 's/^/      /'
    rc=1
  fi
done
if [ $rc -eq 0 ]; then echo "standalone .inc harnesses: $n compiled"; fi
rm -rf "$OUT"
exit $rc
