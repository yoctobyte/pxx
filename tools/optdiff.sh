#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# optdiff.sh — O-level differential sweep (Track T, testmgr --tier opt).
#
# Every standalone-runnable test program (test/*.pas, test/*.c) must behave
# identically at -O0 / -O1 / -O2 / -O3: same stdout+stderr, same exit code. A DIFF
# is the silent-miscompile class this sweep exists to catch — highest
# severity Track T can detect. Port of the manual v196 promotion harness
# (feature-testmgr-opt-tier-and-benchmarks).
#
#   tools/optdiff.sh [--shard i/N]     testmgr shards this across jobs
#
# Skips (never diffs): programs that don't compile or that time out at -O0,
# and the patterns in tools/optdiff.skip (known-nondeterministic output).
# Every skip is now LISTED BY NAME and reason, not just counted — see the
# report block at the bottom for why.
set -u
cd "$(dirname "$0")/.." || exit 1
CC=${TESTMGR_COMPILER:-compiler/pascal26}
TMP=${TESTMGR_TMP:-${TMPDIR:-/tmp}}/optdiff.$$
SCALE=${TESTMGR_TIME_SCALE:-1}
# 30s base: the slowest legit programs (lib_x509 ~5s solo) run under
# full shard parallelism — a tight cap turns box load into false DIFFs
TMO=$(awk "BEGIN{printf \"%d\", 30*$SCALE}")
SHARD=0; NSHARD=1
if [ "${1:-}" = "--shard" ] && [ -n "${2:-}" ]; then
  SHARD=${2%%/*}; NSHARD=${2##*/}
fi
mkdir -p "$TMP" || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

# C tests include crtl headers by path, and the Makefile passes these on every
# such recipe. optdiff used to compile with a bare `$(CC) file`, so 9 of the 18
# test/cmath*.c failed with `C include file not found: "ctype.c"` and were
# counted as skips — invisibly, since a skip-for-lack-of-flags and a skip-for-
# not-being-standalone look identical in a count. Half the correctly-rounded
# libm family, which is exactly where an -O3 float pass would show up and the
# source of the only two DIFFs optdiff has ever reported, was never swept.
#
# Passed unconditionally for *.c rather than tracked per test: a sidecar flags
# table is a second place the truth lives and would drift from the Makefile.
# Extra -I paths are harmless to a test that does not need them.
CFLAGS_C="-Ilib/crtl/include -Ilib/crtl/include/sys -Ilib/crtl/src"

cflags_for() {
  case "$1" in *.c) echo "$CFLAGS_C" ;; *) echo "" ;; esac
}

skip_match() {
  while IFS= read -r pat; do
    case "$pat" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2254  # unquoted on purpose: glob match
    case "$1" in $pat) return 0 ;; esac
  done < tools/optdiff.skip
  return 1
}

# Shard membership is derived from a hash of the BASENAME, not from position.
#
# It used to be `n % NSHARD` over the glob, so adding any test file -- which
# happens with nearly every fix -- shifted every later file into a different
# shard. Since the shard index IS the job identity in tstate, one migration
# manufactured a phantom NEW-RED on the shard a failure moved TO and a phantom
# FIXED on the one it left. Observed 2026-08-01: the same unchanged
# crtl_libc_oracle.c failure re-filed itself three times as it walked
# shard 5 -> 0 -> 2, producing three tickets for one compiler bug.
#
# A name hash is stable under insertion: adding a file moves only that file.
# (Changing NSHARD still reshuffles everything -- unavoidable for any pure
# function of the name -- so change it only when the matrix is green.)
#
# One awk pass, no per-file process spawn: 1276 files x NSHARD shards would be
# thousands of forks otherwise.
FILES=$(ls test/*.pas test/*.c 2>/dev/null | awk -v s="$SHARD" -v n="$NSHARD" '
  BEGIN { for (i = 32; i < 127; i++) ord[sprintf("%c", i)] = i }
  { name = $0; sub(/^.*\//, "", name); h = 0
    for (i = 1; i <= length(name); i++)
      h = (h * 31 + ord[substr(name, i, 1)]) % 1000003
    if (h % n == s) print }')

n=0; pass=0; skip=0; diff=0
skip_listed=""; skip_build=""; skip_timeout=""; recovered=""
for t in $FILES; do
  [ -e "$t" ] || continue
  n=$((n + 1))
  b=$(basename "$t")
  CF=$(cflags_for "$t")
  if skip_match "$b"; then
    skip=$((skip + 1)); skip_listed="$skip_listed $b"; continue
  fi
  # shellcheck disable=SC2086  # CF is a flag list, split on purpose
  # -O0 EXPLICITLY. The baseline used to be built with no -O flag at all, which
  # is -O2 (compiler.pas:908) -- so the `for L in 1 2 3` loop compared -O2
  # against -O2 and that arm could not report a difference under any
  # circumstances. A guard that cannot fail is not a guard, and this one printed
  # PASS for every program in the corpus. The header above and the `d0` naming
  # both already said -O0 was the baseline; the code was the half that was
  # wrong. Positive control for the change, measured 2026-09-01 on
  # test_threadsafe_refcount_lockfree: FAILED at -O0/-O1 and OK at -O2/-O3, so
  # it must now report DIFF on the -O2 and -O3 arms, which were unreportable
  # before. Nothing else in shard 2 changes verdict.
  #
  # THAT CONTROL IS SPENT, 2026-09-02, and is left here as a record of what was
  # measured rather than as something a reader can re-run. The divergence it
  # names was the TEST asserting an -O2-only representation, not a miscompile:
  # EmitStaticLitHandle (compiler/ir_codegen.inc) is gated `OptLevel < 2`, so a
  # literal is the static block in the image at -O2 and above and a
  # PXXStrFromLit heap copy below it, and the test read the static block's
  # saturated refcount as the only correct answer. Both representations were
  # right. The test now branches on MSTR_FLAG_STATIC and is GREEN at every
  # level, so it no longer reports DIFF on any arm and CANNOT be used to show
  # that this baseline is -O0.
  #
  # Anyone changing the baseline again therefore needs a NEW control and must
  # not take the paragraph above as a live one. The cheap way to make one is the
  # way that paragraph was made: build any program at -O0 and at -O2, confirm
  # the bytes differ, and confirm this loop says so — an -O2-against--O2
  # baseline reports PASS for every program in the corpus, which is what it did
  # for as long as the bug existed and is exactly what a dead control looks like
  # from the outside.
  if ! "./$CC" $CF -O0 "$t" "$TMP/d0" >/dev/null 2>&1; then
    # RETRY WITH --threadsafe BEFORE CALLING IT A SKIP. Any program that reaches
    # __pxxclone -- through palthread, classes, TThread, the parallel-for
    # lowering -- is REFUSED without the flag since the directive-without-flag
    # became a hard error, and the Makefile passes it on exactly those recipes.
    # optdiff counts a build-fail as a skip, so those programs left the sweep
    # silently: SEVEN of shard 2's twenty-four skips, and with them the -O3 DCE
    # miscompile that had five shards reporting `rc 0 vs 124`. Once they stopped
    # building, those shards would have gone GREEN with the bug still live. A
    # guard that cannot fail is not a guard.
    #
    # ASK THE COMPILER, DO NOT GREP THE SOURCE. Grepping for {$threadsafe on}
    # looks like the obvious predicate and it is wrong -- measured 2026-09-01:
    # all seven of shard 2's threading build-fails carry the directive ZERO
    # times. The refusal is raised inside lib/rtl/palthread.pas, not in the
    # test. A source-text predicate would have reinstated the same blind spot
    # while reading as a fix, which is why the retry asks the only oracle that
    # cannot go stale. The other seventeen skips in that shard do NOT recover,
    # and eight of them are `*_fail.pas` that must not: the retry distinguishes
    # them for free, where a grep would have had to know about them.
    # THE RESIDUAL, AND IT IS NOT COVERED BY THIS RETRY. A program that NEEDS
    # --threadsafe but still BUILDS without it never reaches this arm. That is
    # every program whose threads come from somewhere other than __pxxclone --
    # a libc pthread_create in its own source, or a linked C library that
    # starts its own -- because the refusal is raised by __pxxclone's lowering
    # and nothing else. Such a program compiles clean, races an allocator with
    # no lock, and reports a DIFF that is not about the compiler. Measured
    # 2026-09-01: shard 9 said `rc 1 vs 139` on
    # test_heap_magazine_foreign_thread.pas, which was mine, added that
    # afternoon, and missing {$THREADSAFE ON}. One instance, now closed, and no
    # others in the Pascal corpus -- but the FIX for the class is in the test
    # (carry the directive, which makes the flagless build a hard error), not
    # here, because a harness cannot tell "needs the flag" from "does not" by
    # looking at a program that builds either way.
    if [ "${t%.c}" = "$t" ] && "./$CC" --threadsafe -O0 "$t" "$TMP/d0" >/dev/null 2>&1; then
      CF="$CF --threadsafe"; recovered="$recovered $b"
    else
      skip=$((skip + 1)); skip_build="$skip_build $b"
      continue                            # doesn't build at -O0: not a diff
    fi
  fi
  o0=$(timeout "$TMO" "$TMP/d0" </dev/null 2>&1); r0=$?
  if [ "$r0" -ge 124 ]; then
    skip=$((skip + 1)); skip_timeout="$skip_timeout $b"; continue
  fi
  ok=1
  # -O1 was the one level with no coverage anywhere in the matrix: the gate
  # tiers compile at the default -O, and this sweep skipped straight from the
  # -O0 baseline to -O2. Track O asked for four-level agreement
  # (chore-t-nothing-in-the-matrix-runs-o3-so-no-failures-is-unfalsifiable) and
  # this is the half of that ask which was genuinely missing.
  #
  # Measured cost 2026-08-28 on shard 0/60, same binary both halves:
  # 49.5s -> 65.3s, +32% -- the 3-compiles-to-4 ratio, as predicted, so the
  # ~20min full sweep becomes ~27min. It lands only on idle watcher cycles and
  # the tier stays preemptible, which is why this is a tier-composition change
  # rather than a request. Revert by dropping the 1.
  for L in 1 2 3; do
    # shellcheck disable=SC2086  # CF is a flag list, split on purpose
    if ! "./$CC" $CF "-O$L" "$t" "$TMP/d$L" >/dev/null 2>&1; then
      echo "OPT COMPILE-DIFF -O$L: $t"
      ok=0; continue
    fi
    oL=$(timeout "$TMO" "$TMP/d$L" </dev/null 2>&1); rL=$?
    if [ "$oL" != "$o0" ] || [ "$rL" -ne "$r0" ]; then
      echo "OPT DIFF -O$L: $t (rc $r0 vs $rL)"
      ok=0
    fi
  done
  if [ "$ok" -eq 1 ]; then pass=$((pass + 1)); else diff=$((diff + 1)); fi
done
# Name every skip. A count alone cannot distinguish "deliberately excluded" from
# "this sweep does not know how to build it", and that is precisely how the
# cmath hole survived: `skip=16` read as a decision somebody had made.
# BUILD-FAIL is the line to read — each entry is a test the O-level sweep is
# NOT covering, for a reason nobody has vouched for.
[ -n "$skip_listed" ]  && echo "optdiff skip SKIPLIST:$skip_listed"
[ -n "$skip_timeout" ] && echo "optdiff skip TIMEOUT-O0:$skip_timeout"
[ -n "$skip_build" ]   && echo "optdiff skip BUILD-FAIL:$skip_build"
# Name the recovered ones too. They are the population this sweep silently lost
# once already, so the line has to be READ, not just counted -- an empty
# THREADSAFE line on a shard that used to print names is the same regression
# coming back, and it looks exactly like good news.
[ -n "$recovered" ]    && echo "optdiff THREADSAFE-RETRY:$recovered"
echo "optdiff shard $SHARD/$NSHARD: pass=$pass skip=$skip diff=$diff"
[ "$diff" -eq 0 ]
