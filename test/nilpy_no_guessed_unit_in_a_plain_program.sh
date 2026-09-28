# SPDX-License-Identifier: MPL-2.0
#
# A plain Nil Python program must not load `math` or `palthreadobj`.
#
# Both are pulled AMBIENTLY by a token guess in ParseUsesUnitBody: a unit whose
# source mentions `pi`, or `sqrt(`/`ln(`/`exp(`/..., or BeginThread/TThreadID,
# gets them for free, because FPC keeps those names in System and portable
# units call them with no `uses`. The compiler's own runtime units
# (compiler/builtin/) are compiled into EVERY program, so a guess fired by one
# of their tokens loaded the unit into every program -- and a loaded unit is a
# scope user code can see. PromoCmpDbl's `var pi` (cafc739cbf) did exactly
# that: `math`'s float Max/Min then answered `max(1.5, 2)` as 2.0 and a user
# `e = getattr(...)` met a unit-level `e`. The fix exempts builtins from the
# guess by WHERE they live, not by name.
#
# This row catches the next one no matter which builtin or which name trips
# it: it reads the unit list the compiler reports (PXXDBG a.units) for a
# program that imports nothing, and fails if either guessed unit is in it.
# It also asserts the probe is live -- a `builtin=1` row for promocore -- so a
# silent probe cannot read as a pass.
#
# Usage: sh test/nilpy_no_guessed_unit_in_a_plain_program.sh <pxx> <tmpdir>
set -e
PXX=${1:?usage: nilpy_no_guessed_unit_in_a_plain_program.sh <pxx> <tmpdir>}
TMP=${2:?usage: nilpy_no_guessed_unit_in_a_plain_program.sh <pxx> <tmpdir>}

# The program runs the builtins' big-int and float/int paths but names none of
# the guessed identifiers itself and has no `**`: the program-level scan pulls
# `math` for a user `pi` (a size cost) and `**` imports it QUALIFIED-ONLY for
# pow, and either would put `math` in the list for reasons that are not this.
SRC=$TMP/no_guessed_unit.npy
LOG=$TMP/no_guessed_unit.units
cat > "$SRC" <<'EOF'
big = 18446744073709551616
print(max(1.5, 2), min(-0.0, 0.0), big > 1.5, str(-big), hex(big))
EOF

PXXDBG=a.units "$PXX" "$SRC" "$TMP/no_guessed_unit" > "$LOG" 2>&1

if ! grep -q '^PXXDBG a\.units promocore builtin=1 ' "$LOG"; then
  echo "FAIL: nilpy_no_guessed_unit — the a.units probe did not report promocore as builtin=1; the row measured nothing."
  exit 1
fi
bad=$(grep -E '^PXXDBG a\.units (math|palthreadobj) ' "$LOG" || true)
if [ -n "$bad" ]; then
  echo "FAIL: nilpy_no_guessed_unit — a program importing nothing loaded a guessed unit:"
  printf '%s\n' "$bad" | sed 's/^/    /'
  echo "  A token in a compiler/builtin unit fired ParseUsesUnitBody's math/thread guess."
  exit 1
fi
units=$(grep -c '^PXXDBG a\.units ' "$LOG")
echo "  test-nilpy: a plain program loads no guessed unit ($units units, math/palthreadobj absent)"
