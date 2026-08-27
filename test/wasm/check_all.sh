#!/bin/sh
# Every wasm lane check, with one verdict.
#
# This exists because a suite went red and stayed red without anyone noticing.
# Each check was run by hand, individually, and the phase 1 compile failure was
# masked twice over: once by `bash check_phase1.sh | tail -6`, which reports
# TAIL's exit status and prints nothing when the script dies early, and once by
# being chained after another check with `&&`, which the same pipe had already
# turned into a success. A pipeline's status is its LAST command's — so nothing
# status-bearing goes upstream of a pipe here.
set -e
here=$(cd "$(dirname "$0")" && pwd)
fail=0
for c in proto/check.sh check_phase1.sh check_phase2.sh; do
  echo "=== $c ==="
  if sh "$here/$c"; then :; else
    echo "FAIL $c"
    fail=1
  fi
done
if [ "$fail" -ne 0 ]; then
  echo "wasm: at least one check FAILED"
  exit 1
fi
echo "wasm: all checks passed"
