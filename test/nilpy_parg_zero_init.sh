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
# POSITIVE CONTROLS, both required, because a census that enumerates nothing
# passes silently and this suite has been bitten by exactly that:
#   1. at least one `__py_parg_` row must EXIST (else the subject is absent and
#      the check is vacuous -- e.g. someone renames PyHiddenName's prefix);
#   2. at least one STORE line must be printed (else the probe is not reporting
#      stores at all and "no missing store" is meaningless).
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
