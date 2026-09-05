#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# THE TRIGGER FOR THE 32-BIT `va_arg` SET, MADE EXECUTABLE.
#
# bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet
# records that cparser.inc's four `TargetArch in [TARGET_I386, TARGET_ARM32,
# TARGET_RISCV32, TARGET_XTENSA]` sites are complete and correct FOR A REASON
# THAT HAS NOTHING TO DO WITH THE SET: the members that would falsify it cannot
# compile a C program at all. Its defence is a sentence telling whoever
# implements the missing entry stub to widen the set in the same commit. This
# script is that sentence with a failing exit code behind it.
#
# WHAT IT ASSERTS, PER TARGET, AND WHY BOTH ARMS ARE NEEDED:
#
#   builds   -> the three va_arg values must equal gcc's, exactly. A target
#               that fell into the `TargetArch <> TARGET_X86_64` arm gets
#               aarch64's 8-byte two-bank layout and produces WRONG VALUES with
#               no diagnostic, starting at the second argument.
#   refuses  -> the refusal must name the C ENTRY STUB. That is the only
#               licence for a target to be outside this test's reach, and it is
#               exactly the thing somebody is going to implement. A target that
#               refuses for any OTHER reason is a target this script has
#               stopped covering without saying so.
#
# The second arm is the whole point. Without it, a C frontend that broke for
# every cross target would turn this script green: every row would "refuse",
# and refusing is a pass in the naive version. That is the shape this repo
# keeps meeting -- an absence that belongs to the instrument being read as an
# absence in the world.
#
# THE EXPECTED LINE COMES FROM gcc, NOT FROM HERE. The claim is that the answer
# is target-INDEPENDENT, so a per-target constant table would be a second copy
# of the knowledge under test and would rot the way width tables do.
#
# Exits nonzero on any failure and prints VA-ARG-EVERY-TARGET-COMPLETE on
# success -- a positive token, because an exit status can come from a shell
# that never ran the body.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
COMPILER="${PXX_COMPILER:-./compiler/pascal26}"
SRC=test/c_va_arg_every_target.c
WORK="$(mktemp -d "${TMPDIR:-/tmp}/vaarg-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Every target the compiler can be asked for. Adding one here is deliberate:
# this list is what makes a NEW target visible to this check on the day it
# lands rather than the day someone remembers.
TARGETS="x86_64 i386 arm32 riscv32 aarch64 xtensa wasm32"

fail() { printf 'c_va_arg_every_target: FAIL - %s\n' "$*" >&2; exit 1; }

# ---- the oracle -------------------------------------------------------------
command -v gcc >/dev/null 2>&1 || fail "no gcc: there is no oracle, so there is no result"
gcc -std=gnu99 -o "$WORK/oracle" "$SRC" >"$WORK/oracle.log" 2>&1 \
  || { cat "$WORK/oracle.log" >&2; fail "gcc could not build the subject -- no oracle, so no result"; }
EXPECT="$("$WORK/oracle")"
# ASSERT THE ORACLE RAN. An empty expectation makes every comparison below pass
# against every target that also printed nothing.
[ -n "$EXPECT" ] || fail "the gcc oracle printed nothing -- comparing against an empty string would pass on anything"
case "$EXPECT" in
  1122334455667788*) : ;;
  *) fail "the gcc oracle printed '$EXPECT', which does not carry the 64-bit argument this test is about" ;;
esac
printf '  oracle   gcc: %s\n' "$EXPECT"

built=0; refused=0; examined=0
for t in $TARGETS; do
  examined=$((examined + 1))
  if [ "$t" = x86_64 ]; then tf=""; else tf="--target=$t"; fi
  if "$COMPILER" $tf "$SRC" "$WORK/va_$t" >"$WORK/build_$t.log" 2>&1; then
    if [ "$t" = x86_64 ]; then got="$("$WORK/va_$t" 2>&1)"
    else got="$(tools/run_target.sh "$t" "$WORK/va_$t" 2>&1)"; fi
    # run_target.sh prints an absent runner on STDOUT precisely so this
    # comparison sees it as a mismatch rather than as an empty pass.
    [ "$got" = "$EXPECT" ] \
      || fail "$t built and printed '$got', gcc says '$EXPECT' -- a target in the wrong va_arg slot-width set prints exactly this way"
    printf '  %-9s builds   %s\n' "$t" "$got"
    built=$((built + 1))
  else
    grep -q 'C program entry stub' "$WORK/build_$t.log" \
      || fail "$t refused for a reason that is NOT the C entry stub, so this check silently stopped covering it: $(grep -m1 'error:' "$WORK/build_$t.log")"
    printf '  %-9s refuses  no C entry stub yet -- outside this check by construction, and the trigger\n' "$t"
    refused=$((refused + 1))
  fi
done

# THE DENOMINATOR, and the guard against a run where nothing happened. If the
# frontend broke for every cross target, `refused` would be 6 and `built` 1 --
# so a floor on `built` is what separates "the set is right" from "nothing ran".
[ "$examined" -eq 7 ] || fail "examined $examined targets, expected 7 -- the list changed without this floor moving"
[ "$built" -ge 5 ] \
  || fail "only $built target(s) built a va_arg program; this check cannot say anything about a set it never reached"

printf '  %d built, %d awaiting a C entry stub, %d examined\n' "$built" "$refused" "$examined"
printf 'VA-ARG-EVERY-TARGET-COMPLETE\n'
