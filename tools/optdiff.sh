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
set -u
cd "$(dirname "$0")/.." || exit 1
CC=${TESTMGR_COMPILER:-compiler/pascal26}
TMP=${TESTMGR_TMP:-${TMPDIR:-/tmp}}/optdiff.$$
SCALE=${TESTMGR_TIME_SCALE:-1}
TMO=$(awk "BEGIN{printf \"%d\", 10*$SCALE}")
SHARD=0; NSHARD=1
if [ "${1:-}" = "--shard" ] && [ -n "${2:-}" ]; then
  SHARD=${2%%/*}; NSHARD=${2##*/}
fi
mkdir -p "$TMP" || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

skip_match() {
  while IFS= read -r pat; do
    case "$pat" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2254  # unquoted on purpose: glob match
    case "$1" in $pat) return 0 ;; esac
  done < tools/optdiff.skip
  return 1
}

n=0; pass=0; skip=0; diff=0
for t in test/*.pas test/*.c; do
  [ -e "$t" ] || continue
  n=$((n + 1))
  [ $((n % NSHARD)) -eq "$SHARD" ] || continue
  b=$(basename "$t")
  if skip_match "$b"; then skip=$((skip + 1)); continue; fi
  if ! "./$CC" "$t" "$TMP/d0" >/dev/null 2>&1; then
    skip=$((skip + 1)); continue          # doesn't build at -O0: not a diff
  fi
  o0=$(timeout "$TMO" "$TMP/d0" </dev/null 2>&1); r0=$?
  if [ "$r0" -ge 124 ]; then skip=$((skip + 1)); continue; fi
  ok=1
  for L in 2 3; do
    if ! "./$CC" "-O$L" "$t" "$TMP/d$L" >/dev/null 2>&1; then
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
echo "optdiff shard $SHARD/$NSHARD: pass=$pass skip=$skip diff=$diff"
[ "$diff" -eq 0 ]
