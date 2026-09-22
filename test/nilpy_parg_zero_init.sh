#!/bin/sh
# Every managed `print()` ARGUMENT TEMP must get a prologue zero-init store.
#
# WHAT THIS GUARDS, and why the obvious test does not guard it. pyparser mints a
# hidden local per print() argument (`__py_parg_N`) so Python's
# evaluate-every-argument-before-writing order holds. That temp is managed, its
# hoisted assignment RELEASES the destination before writing it, and for a
# promotable int the release dereferences the slot's tag -- so a temp that is
# never zeroed releases whatever the previous frame left. Live bug, shipped
# default, rc=139:
#   bug-a-the-nilpy-print-promo-argument-temp-is-never-zero-initialised
#
# THE OBVIOUS TEST -- run the repro, assert rc=0 -- IS A GUARD THAT CANNOT FAIL.
# It passes on the BROKEN compiler whenever the stale bytes at that frame offset
# do not happen to read {PROMO_TAG_HEAP, <non-static pointer>}. Measured on the
# unfixed compiler: the same nine-line program is rc=139 alone and rc=0 with one
# unrelated call placed in front of it, BYTE-IDENTICAL source either way; and the
# two-local and four-local spellings of it were clean throughout while carrying
# the identical defect at a different offset. An rc assertion here measures a
# lottery, and it was winning for three of the four -O levels.
#
# So this asserts the STRUCTURAL property instead, which is deterministic: every
# parg temp the walk visits must have a zero-init store emitted for it. It reads
# PXXDBG=a.htemp, which prints one row per symbol the hidden-arg-temp prologue
# walk sees (`in=` inside its bounds, `htemp=` the flag) and a STORE line from
# inside each arm at the point it stores. No objdump, no section headers, no host
# tooling -- the compiler is the only instrument.
#
# THE POPULATION a.htemp ITERATES, stated here because the guard's validity turns
# on it and it is NOT inferable from reading this script. The probe's enumeration
# loop (ir_codegen.inc, `PXXDBG a.htemp`) is
#     for i := 0 to SymCount - 1 do
#       if i >= Procs[CurProc].ScopeBase - 24 then WriteLn(... ' htemp=', ...)
# — it walks EVERY symbol in a window that deliberately starts below the walk's
# own ScopeBase, and prints `htemp=` as a COLUMN. It is not filtered by the flag.
#
# That is load-bearing and not an implementation detail. Had the probe instead
# enumerated only the symbols the hidden-arg-temp walk VISITS — a set the walk
# itself filters by SymIsHiddenArgTemp — this guard would be keyed on the
# PRESENCE of the very property whose ABSENCE was the defect, a future unflagged
# temp would be invisible to it, and it would be a guard that cannot fail for the
# bug it was written for. (That is the absence-keyed-guarantee class in
# debugging-playbook.md arriving inside the guard against it; frankz-e5 asked the
# question.) The negative control below is what PROVES the first reading: on the
# unfixed compiler the dump printed four rows at `htemp=0`, so unflagged temps do
# appear and a recurrence of exactly this bug is visible to this check.
#
# POSITIVE CONTROLS, both required, because a census that enumerates nothing
# passes silently and this suite has been bitten by exactly that:
#   1. at least one `__py_parg_` row must EXIST (else the subject is absent and
#      the check is vacuous -- e.g. someone renames PyHiddenName's prefix);
#   2. at least one STORE line must be printed (else the probe is not reporting
#      stores at all and "no missing store" is meaningless).
#
# TAKES THE BUILT COMPILER, NOT $(PXX_STABLE), AND THAT IS NOT INTERCHANGEABLE.
# The fix this gates is a COMPILER change, so it is inert in the pin until a pin
# carries it: wired to the pinned binary this row would be RED today for the
# right reason, and then go GREEN the moment v419 lands for a reason that has
# nothing to do with the tree under test. A test of the pin is a test of a
# different compiler.
#
# NEGATIVE CONTROL, RUN RATHER THAN ASSERTED (2026-09-22, frankb-8e): reverting
# the one-line fix at the mint site and rebuilding made this script FAIL, naming
# all four parg temps — sym 559 `__py_parg_9` tk=28, 560 `__py_parg_10` tk=23,
# 561 tk=28, 562 tk=28, every one `htemp=0` with no store. Restoring rebuilt to
# the byte-identical fixed binary. Two things came out of running it: the
# reverted build reproduced the pre-fix sha EXACTLY (`4a109b04af0d`), so the
# revert was provably the same tree rather than a similar one; and `tk=23` is an
# ANSISTRING parg, which is what turns "this defect was never promo-specific"
# from an argument about how pargTk is computed into a measurement.
#
# Usage: sh test/nilpy_parg_zero_init.sh <pxx> <tmpdir>
set -e
PXX=${1:?usage: nilpy_parg_zero_init.sh <pxx> <tmpdir>}
TMP=${2:?usage: nilpy_parg_zero_init.sh <pxx> <tmpdir>}

SRC=$TMP/parg_zero_init.npy
LOG=$TMP/parg_zero_init.htemp

# Several managed argument kinds, because pargTk is whatever the argument's type
# is -- promo is merely where the defect becomes a crash. The bignum forces the
# HEAP tier, which is the tag the release path mis-read.
cat > "$SRC" <<'EOF'
def main():
    v0 = 0
    acc = 0
    i = 0
    while i < 3:
        acc = acc + 1
        i = i + 1
    s = "text"
    big = 12345678901234567890
    print(acc)
    print(s, acc, big)

main()
EOF

PXXDBG=a.htemp "$PXX" -O2 "$SRC" "$TMP/parg_zero_init.bin" > "$LOG" 2>&1 || {
  echo "FAIL: nilpy_parg_zero_init — compile failed"; tail -20 "$LOG"; exit 1; }

# main's block only: from its RANGE line to the next proc's RANGE line.
BLOCK=$TMP/parg_zero_init.block
awk '/a\.htemp RANGE proc=main /{f=1} f&&/a\.htemp RANGE proc=/&&!/proc=main /{exit} f' \
  "$LOG" > "$BLOCK"

pargs=$(grep -c 'a\.htemp sym=.* in=1 name=\[__py_parg_' "$BLOCK" || true)
stores=$(grep -c 'a\.htemp STORE sym=' "$BLOCK" || true)

# Control 1: the subject must be present.
if [ "$pargs" -lt 1 ]; then
  echo "FAIL: nilpy_parg_zero_init — no __py_parg_ rows in main's a.htemp block."
  echo "      The check is vacuous, not passing. Has PyHiddenName's prefix or the"
  echo "      a.htemp row format changed? Block follows:"
  sed -n '1,40p' "$BLOCK"
  exit 1
fi

# Control 2: the probe must be able to print a store at all.
if [ "$stores" -lt 1 ]; then
  echo "FAIL: nilpy_parg_zero_init — a.htemp printed no STORE line for main."
  echo "      'no missing store' cannot be trusted from an instrument that"
  echo "      reports no stores. Block follows:"
  sed -n '1,40p' "$BLOCK"
  exit 1
fi

# The assertion: every visited parg temp has a STORE for its sym index.
missing=0
for sym in $(sed -n 's/.*a\.htemp sym=\([0-9]*\) in=1 name=\[__py_parg_.*/\1/p' "$BLOCK"); do
  if ! grep -q "a\.htemp STORE sym=$sym " "$BLOCK"; then
    echo "FAIL: nilpy_parg_zero_init — sym=$sym is a __py_parg_ temp with NO zero-init store."
    grep "a\.htemp sym=$sym " "$BLOCK" || true
    missing=$((missing + 1))
  fi
done

if [ "$missing" -gt 0 ]; then
  echo "      $missing parg temp(s) reach the epilogue's release holding stale stack bytes."
  echo "      The mint site must set SymIsHiddenArgTemp (pyparser.inc, PyHiddenName('parg'))."
  exit 1
fi

echo "  test-nilpy: every print() argument temp is zero-initialised ($pargs parg, $stores store)"
