#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# optfuzz.sh — O-level SELF-differential fuzzer (Track T tooling; born
# 2026-07-18 night, fable-O). pasmith-generated programs compiled at
# -O0/-O2/-O3 with the SAME compiler; any stdout+exit divergence = a silent
# optimizer miscompile. First 10-minute run caught the depth-1 re-inline
# divergence (reverted a3f6e70a) that the whole curated gate battery missed —
# the optdiff corpus is too tame for inliner/allocator state bugs; random
# programs are not.
#
#   tools/optfuzz.sh [SECONDS] [OUTDIR]     (default 600s, cwd)
#
# Repros land as OUTDIR/bad_<seed>.pas. Time-boxed; clean run = valid result.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="${2:-$PWD}"
CC="${OPTFUZZ_CC:-$ROOT/compiler/pascal26}"
N=0; DIFFS=0; CFAIL=0
END=$((SECONDS + ${1:-600}))
while [ $SECONDS -lt $END ]; do
  seed=$((RANDOM * 32768 + RANDOM))
  python3 "$ROOT"/tools/pasmith.py --seed $seed -o $S/fz.pas \
    --funcs 6 --stmts 14 --depth 3 --vars 8 --recs 2 --arrs 2 --enums 1 \
    --excepts 1 --classes 2 --objs 2 --strs 2 2>/dev/null || continue
  $CC -O0 $S/fz.pas $S/fz0 >/dev/null 2>&1 || { CFAIL=$((CFAIL+1)); continue; }
  $CC -O2 $S/fz.pas $S/fz2 >/dev/null 2>&1 || { echo "COMPILE-DIFF O2 seed=$seed"; cp $S/fz.pas $S/bad_$seed.pas; DIFFS=$((DIFFS+1)); continue; }
  $CC -O3 $S/fz.pas $S/fz3 >/dev/null 2>&1 || { echo "COMPILE-DIFF O3 seed=$seed"; cp $S/fz.pas $S/bad_$seed.pas; DIFFS=$((DIFFS+1)); continue; }
  o0=$(timeout 10 $S/fz0 2>&1; echo "ex=$?")
  o2=$(timeout 10 $S/fz2 2>&1; echo "ex=$?")
  o3=$(timeout 10 $S/fz3 2>&1; echo "ex=$?")
  if [ "$o0" != "$o2" ] || [ "$o0" != "$o3" ]; then
    echo "RUNTIME-DIFF seed=$seed (O2 same: $([ "$o0" = "$o2" ] && echo y || echo N), O3 same: $([ "$o0" = "$o3" ] && echo y || echo N))"
    cp $S/fz.pas $S/bad_$seed.pas
    DIFFS=$((DIFFS+1))
  fi
  N=$((N+1))
done
echo "optfuzz: $N programs differenced, $DIFFS diffs, $CFAIL o0-compile-skips"
