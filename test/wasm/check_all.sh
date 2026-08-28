#!/bin/sh
# Every wasm lane check, with one verdict.
#
# This exists because a suite went red and stayed red across a handoff that
# reported it green. Two things had to be true for that, and both are fixed
# here rather than remembered:
#
#   1. The checks were run individually and by hand, piped into `tail`. A
#      pipeline's exit status is its LAST command's, so `check_phase1.sh |
#      tail -6` reported tail's success. Chained with `&&`, a run of piped
#      checks cannot fail at all — it reports the health of `tail`.
#
#   2. More fundamentally, green looked like the ABSENCE of output. That is
#      indistinguishable from a script that died at line 1, which is exactly
#      what had happened. The pipe inverted the check only because the check
#      had no positive sentinel to lose. (The rule, from frankB via the
#      coordinator: a piped check is safe iff it prints something failure
#      cannot reach.)
#
# So each check now ends with `PASS <name>` — unreachable under `set -e` unless
# everything above it passed — and this script asserts that line is PRESENT.
# Exit status is still checked, belt and braces, but the sentinel is what makes
# a truncated, killed or half-run check fail loudly instead of quietly.
set -e
here=$(cd "$(dirname "$0")" && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-all.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

fail=0
for c in proto/check.sh check_phase1.sh check_phase2.sh check_phase3.sh check_phase4.sh check_data.sh; do
  name=$(basename "$c" .sh)
  echo "=== $c ==="
  if sh "$here/$c" > "$work/out.txt" 2>&1; then status=0; else status=$?; fi
  cat "$work/out.txt"
  if [ "$status" -ne 0 ]; then
    echo "FAIL $c (exit $status)"
    fail=1
  elif ! grep -qx "PASS $name" "$work/out.txt"; then
    # Exited 0 without reaching its own last line: killed, truncated, or the
    # sentinel was removed. Either way it did not finish, and a zero exit is
    # not evidence that it did.
    echo "FAIL $c (exit 0 but no 'PASS $name' sentinel — it did not finish)"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "wasm: at least one check FAILED"
  exit 1
fi
echo "wasm: all checks passed"
