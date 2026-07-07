#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# c-testsuite conformance runner (feature-c-corpus-expansion step 1).
#
# Runs the vendored c-testsuite single-exec battery (220 single-file C
# conformance programs) against the pxx C frontend. Contract per upstream:
# `main` is the entry point, exit code must be 0, and combined stdout+stderr
# must byte-match NNN.c.expected.
#
# We deliberately bypass upstream's runner infra (sh/Python3/TAP/TMSU — their
# CI only). Skips are EXPLICIT: test/c-conformance/pxx.skip lists one test per
# line as "NNN.c<TAB>reason"; anything not passing and not listed = FAIL.
#
# Usage: tools/run_c_conformance.sh [compiler] [suite-dir] [--shard I/N]
#   compiler  default compiler/pascal26
#   suite-dir default library_candidates/c-testsuite/tests/single-exec
#   --shard I/N  run only tests with (index mod N) == I (0-based); lets a
#                parallel harness (tools/testmgr.py) fan the battery out.
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CC="${1:-$ROOT/compiler/pascal26}"
SUITE="${2:-$ROOT/library_candidates/c-testsuite/tests/single-exec}"
SHARD_I=0; SHARD_N=1
case "${3:-}" in
  --shard)  SHARD_I="${4%%/*}"; SHARD_N="${4##*/}" ;;
  --shard=*) v="${3#--shard=}"; SHARD_I="${v%%/*}"; SHARD_N="${v##*/}" ;;
esac
SKIPLIST="$ROOT/test/c-conformance/pxx.skip"
WORK="${TMPDIR:-/tmp}/pxx_c_conformance.$$"
# per-program run budget; stretched by testmgr's calibration factor so weak
# hardware doesn't false-timeout (TESTMGR_TIME_SCALE, default 1)
TIMEOUT_S="$(awk -v s="${TESTMGR_TIME_SCALE:-1}" 'BEGIN { t=10*s; printf "%d", (t<10 ? 10 : t) }')"

if [ ! -f "$SUITE/00001.c" ]; then
  echo "test-c-conformance: SKIP — no suite at $SUITE (run tools/install_lib_candidates.sh c-testsuite)"
  exit 0
fi

mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; skip=0; failed=""; idx=-1

for src in "$SUITE"/*.c; do
  name="$(basename "$src")"
  idx=$((idx+1))
  [ $((idx % SHARD_N)) = "$SHARD_I" ] || continue

  # explicit skip-list (tab- or space-separated: name reason)
  if [ -f "$SKIPLIST" ]; then
    reason="$(awk -v n="$name" '$1==n { $1=""; sub(/^[ \t]+/,""); print; exit }' "$SKIPLIST")"
    if [ -n "$reason" ]; then
      skip=$((skip+1))
      echo "SKIP $name — $reason"
      continue
    fi
  fi

  bin="$WORK/${name%.c}"
  if ! "$CC" -Ilib/crtl/include -Ilib/crtl/src "$src" "$bin" \
      > "$WORK/cc.log" 2>&1; then
    fail=$((fail+1)); failed="$failed $name(compile)"
    echo "FAIL $name — compile error:"
    sed -n '1,4p' "$WORK/cc.log" | sed 's/^/    /'
    continue
  fi

  timeout "$TIMEOUT_S" "$bin" > "$WORK/out.txt" 2>&1
  rc=$?
  if [ "$rc" != "0" ]; then
    fail=$((fail+1)); failed="$failed $name(exit=$rc)"
    echo "FAIL $name — exit code $rc (want 0)"
    continue
  fi
  if ! cmp -s "$WORK/out.txt" "$src.expected"; then
    fail=$((fail+1)); failed="$failed $name(output)"
    echo "FAIL $name — output mismatch:"
    diff -u "$src.expected" "$WORK/out.txt" | sed -n '1,8p' | sed 's/^/    /'
    continue
  fi
  pass=$((pass+1))
done

echo "test-c-conformance: $pass pass, $fail fail, $skip skip (of $((pass+fail+skip)))"
if [ "$fail" != "0" ]; then
  echo "test-c-conformance: FAILURES:$failed"
  exit 1
fi
