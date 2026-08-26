#!/usr/bin/env bash
# selfcompile_odiff -- build the compiler at every -O level and diff what the
# results EMIT.
#
# WHY THIS EXISTS
# ---------------
# CLAUDE.md's claims section is explicit about the hole:
#
#   `make compiler/pascal26` builds compiler.pas at the DEFAULT optimisation
#   level, and the fixedpoint proves byte-identity AT THAT LEVEL. [...] "it
#   passes the self-host gate" is evidence the compiler compiles itself at ONE
#   optimisation level, not that it compiles itself -- a -O0-only self-compile
#   failure passed the entire gate on 2026-08-19 and was found by a benchmark.
#
# Found by a benchmark, which is to say: by luck, in a phase that only runs when
# the box is idle.
#
# WHAT IT ASSERTS, AND WHY THAT IS THE INTERESTING PART
# -----------------------------------------------------
# NOT "does -O0 still build". That is the weak version and its motivation is
# already spent -- the 08-19 failure was MAX_CODE, a runaway guard rather than a
# real constraint, since raised 8MB -> 16MB with the default build at 44%.
#
# The lasting assertion is: **a compiler built at -O0 and a compiler built at
# -O3 must EMIT THE SAME BYTES.** Optimising the compiler may change how fast it
# runs; it must not change what it produces. If they disagree, that is an
# optimizer bug, and compiler.pas is the largest, most edge-case-dense program
# available to run the optimizer over. The value grows as Track O ramps up.
#
# COUNTER-INTUITIVE, AND THE REPORTING MUST NOT ASSUME OTHERWISE
# --------------------------------------------------------------
# LOWER -O levels emit MORE code, so a build that fits at -O2 can overflow at
# -O0. Do not read "-O0 failed" as "-O0 is the easy case".
#
# THREE RED ROWS, ONE DEFECT
# --------------------------
# The bench harness this formalises had the baseline bug: when the -O0 build
# failed, every other level reported CANARY-DIFF vs -O0 -- against a baseline
# that was never produced. So the three states are named apart here and a
# missing baseline never uses the word DIFF:
#
#   BUILD-FAIL    this level's compiler did not build
#   NO-BASELINE   -O0 produced nothing, so this level was NOT compared
#   EMIT-FAIL     this level's compiler could not compile the input
#   DIFF          the levels genuinely disagree  <-- the only optimizer finding
#
# Usage: tools/selfcompile_odiff.sh [-q]     (exit 0 = all levels agree)
set -uo pipefail
cd "$(dirname "$0")/.."

CC=${PXX_ODIFF_CC:-./compiler/pascal26}
LEVELS=${PXX_ODIFF_LEVELS:-"-O0 -O1 -O2 -O3"}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/odiff-XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# The differential inputs. compiler.pas first and deliberately: it is the
# densest program we own, and a stage compiling it exercises far more of the
# optimizer than any test case. The rest are cheap breadth over shapes the
# compiler's own source happens not to stress.
INPUTS="compiler/compiler.pas test/test_ansistring.pas test/test_class_of.pas test/test_dynarray_torture.pas test/test_cross_exception.pas"

[ -x "$CC" ] || { echo "odiff: no compiler at $CC (run: make compiler/pascal26)"; exit 2; }

echo "odiff: compiler $CC"
echo "odiff: levels  $LEVELS"

fail=0
built=""
for L in $LEVELS; do
  stage="$TMP/p26${L//-/_}"
  t0=$SECONDS
  if "$CC" "$L" compiler/compiler.pas "$stage" > "$TMP/build$L.log" 2>&1; then
    printf "  BUILD    %-4s ok   %5ds  %9d bytes\n" "$L" "$((SECONDS-t0))" "$(stat -c%s "$stage")"
    built="$built $L"
  else
    # Lower levels emit MORE code, so this is where a size ceiling bites first.
    printf "  BUILD-FAIL %-4s     %5ds  %s\n" "$L" "$((SECONDS-t0))" "$(tail -1 "$TMP/build$L.log")"
    fail=1
  fi
done

# The baseline level: the first one that BUILT, not a hardcoded -O0. If -O0
# failed we can still learn whether the remaining levels agree with each other,
# which is a real optimizer signal and used to be thrown away along with the
# baseline.
base=$(echo $built | awk '{print $1}')
if [ -z "$base" ]; then
  echo "odiff: NO LEVEL BUILT — nothing to compare. This is a build failure, not"
  echo "       an optimizer finding; read the BUILD-FAIL lines above."
  exit 1
fi
[ "$base" != "-O0" ] && echo "odiff: NOTE baseline is $base, not -O0 (-O0 did not build) — the"
[ "$base" != "-O0" ] && echo "odiff:      comparison below is still valid, but it cannot speak about -O0."

for src in $INPUTS; do
  [ -f "$src" ] || { echo "  SKIP     $src (absent)"; continue; }
  ref=""
  for L in $built; do
    stage="$TMP/p26${L//-/_}"
    out="$TMP/out${L//-/_}_$(basename "$src" | tr './' '__')"
    if ! "$stage" "$src" "$out" > "$TMP/emit$L.log" 2>&1 || [ ! -f "$out" ]; then
      printf "  EMIT-FAIL %-4s %s — %s\n" "$L" "$src" "$(tail -1 "$TMP/emit$L.log")"
      fail=1
      continue
    fi
    if [ "$L" = "$base" ]; then
      ref="$out"
      continue
    fi
    if [ -z "$ref" ]; then
      # Named apart from DIFF on purpose: there is nothing to compare against,
      # and calling that a diff is how one defect became three red rows.
      printf "  NO-BASELINE %-4s %s (%s emitted nothing; NOT compared)\n" "$L" "$src" "$base"
      fail=1
      continue
    fi
    if cmp -s "$ref" "$out"; then
      printf "  same     %-4s vs %-4s  %s\n" "$L" "$base" "$src"
    else
      printf "  DIFF     %-4s vs %-4s  %s  (%d vs %d bytes) — optimizing the compiler changed what it emits\n" \
             "$L" "$base" "$src" "$(stat -c%s "$out")" "$(stat -c%s "$ref")"
      fail=1
    fi
  done
done

if [ "$fail" -eq 0 ]; then
  echo "odiff: GREEN — every level that built emits identical bytes"
else
  echo "odiff: RED — see the lines above; only DIFF is an optimizer finding"
fi
exit $fail
