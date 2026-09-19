#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# IS THIS OPERATION SIGNED? ASKED ON EVERY TARGET, AGAINST gcc.
#
# A backend picks div_s or div_u, lt_s or lt_u, from one answer, and a rule
# that is wrong in either direction produces a plausible wrong number rather
# than a crash. test/c_integer_signedness.c carries thirteen shapes chosen so
# that the two directions cannot hide each other; its own header says which
# row exists for which mistake.
#
# WHY A PER-TARGET SCRIPT AND NOT A ROW IN gcc_diff_probe.sh: that harness
# reports KNOWN divergences against the PINNED compiler and has no wasm32 or
# xtensa arm. This is a must-pass guard at HEAD, on all seven, and the defect
# it was written for existed on exactly one of them -- so a check that cannot
# reach that one is a check that could not have found it.
#
# THE ORACLE IS gcc AND THE WHOLE LINE IS DIFFED, so no expected value lives
# here or in the subject. A per-target table would be a second copy of the
# knowledge under test.
#
# AND THE SUBJECT PRINTS ITS MASK RATHER THAN RETURNING IT, which is why the
# diff is of a LINE and not of an exit status. An exit status is 8 bits and
# the mask is 13: the first draft returned `bad ? 100000 + bad : 42` and
# 100000 + 138 is 42 mod 256 -- so three real failures, rows 2, 8 and 128,
# would have exited with the all-pass answer. A guard whose failure value can
# alias onto its pass value is a guard that cannot fail.
#
# EVERY TARGET MUST BUILD AND RUN. There is no admitted-refusal branch on
# purpose: this subject is plain integer arithmetic plus one printf, every
# target in the list builds it today, and a target that stops is a regression
# and not a wall. If you add a target, add it here and make it pass.
#
# Exits nonzero on any failure and prints INT-SIGNEDNESS-EVERY-TARGET-COMPLETE
# on success -- a positive token, because an exit status can come from a shell
# that never ran the body.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
COMPILER="${PXX_COMPILER:-./compiler/pascal26}"
SRC=test/c_integer_signedness.c
WORK="$(mktemp -d "${TMPDIR:-/tmp}/intsign-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

TARGETS="x86_64 i386 arm32 riscv32 aarch64 xtensa wasm32"

fail() { printf 'c_int_signedness_every_target: FAIL - %s\n' "$*" >&2; exit 1; }

command -v gcc >/dev/null 2>&1 || fail "no gcc: there is no oracle, so there is no result"
gcc -std=gnu99 -o "$WORK/oracle" "$SRC" >"$WORK/oracle.log" 2>&1 \
  || { cat "$WORK/oracle.log" >&2; fail "gcc could not build the subject -- no oracle, so no result"; }
EXPECT="$("$WORK/oracle")"
# ASSERT THE ORACLE RAN, and that it ran CLEAN. An empty expectation makes
# every comparison below pass against a target that also printed nothing, and
# a nonzero mask from gcc means the subject itself is wrong rather than any
# backend -- either way there is nothing to compare against.
[ -n "$EXPECT" ] || fail "the gcc oracle printed nothing -- comparing against an empty string would pass on anything"
[ "$EXPECT" = "signs bad=0" ] \
  || fail "gcc itself reports failures ($EXPECT) -- the subject is wrong, not the backends"
printf '  oracle   gcc: %s\n' "$EXPECT"

built=0; examined=0
for t in $TARGETS; do
  examined=$((examined + 1))
  if [ "$t" = x86_64 ]; then tf=""; else tf="--target=$t"; fi
  # xtensa's default profile is the ESP one, which has no standalone entry
  # stub; its hosted-posix profile is the one qemu-xtensa runs. A PROFILE
  # selection, not an expected value -- the same note c_va_arg_every_target.sh
  # carries, and for the same reason.
  case "$t" in
    xtensa) pf="--platform=posix" ;;
    *)      pf="" ;;
  esac
  "$COMPILER" $tf $pf "$SRC" "$WORK/sg_$t" >"$WORK/build_$t.log" 2>&1 \
    || { sed 's/^/    /' "$WORK/build_$t.log" >&2
         fail "$t could not build a plain integer-arithmetic subject"; }
  if [ "$t" = x86_64 ]; then got="$("$WORK/sg_$t" 2>&1)"
  else got="$(tools/run_target.sh "$t" "$WORK/sg_$t" 2>&1)"; fi
  # run_target.sh prints an absent runner on STDOUT precisely so this
  # comparison sees it as a mismatch rather than as an empty pass.
  [ "$got" = "$EXPECT" ] \
    || fail "$t printed '$got', gcc says '$EXPECT' -- each bit names its shape in the subject's header"
  printf '  %-9s %s\n' "$t" "$got"
  built=$((built + 1))
done

[ "$examined" -eq 7 ] || fail "examined $examined targets, expected 7 -- the list changed without this floor moving"
[ "$built" -eq 7 ] || fail "only $built target(s) ran; this check cannot say anything about a set it never reached"

printf '  %d targets, all agreeing with gcc\n' "$built"
printf 'INT-SIGNEDNESS-EVERY-TARGET-COMPLETE\n'
