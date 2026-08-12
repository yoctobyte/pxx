#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# optdiff.sh — O-level differential sweep (Track T, testmgr --tier opt).
#
# Every standalone-runnable test program (test/*.pas, test/*.c) must behave
# identically at -O0 / -O2 / -O3: same stdout+stderr, same exit code. A DIFF
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
skip_listed=""; skip_build=""; skip_timeout=""
for t in $FILES; do
  [ -e "$t" ] || continue
  n=$((n + 1))
  b=$(basename "$t")
  CF=$(cflags_for "$t")
  if skip_match "$b"; then
    skip=$((skip + 1)); skip_listed="$skip_listed $b"; continue
  fi
  # shellcheck disable=SC2086  # CF is a flag list, split on purpose
  if ! "./$CC" $CF "$t" "$TMP/d0" >/dev/null 2>&1; then
    skip=$((skip + 1)); skip_build="$skip_build $b"
    continue                              # doesn't build at -O0: not a diff
  fi
  o0=$(timeout "$TMO" "$TMP/d0" </dev/null 2>&1); r0=$?
  if [ "$r0" -ge 124 ]; then
    skip=$((skip + 1)); skip_timeout="$skip_timeout $b"; continue
  fi
  ok=1
  for L in 2 3; do
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
echo "optdiff shard $SHARD/$NSHARD: pass=$pass skip=$skip diff=$diff"
[ "$diff" -eq 0 ]
