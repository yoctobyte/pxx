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

# THE LIST BELOW IS HAND-MAINTAINED, AND NOTHING TELLS YOU WHEN YOU FORGET.
# Adding check_foo.sh to this directory does NOT run it: this file is the only
# thing that runs the directory, so an unenrolled checker is silent and the
# suite goes on printing green with one fewer row. Two guards landed on
# 2026-09-06 and were invisible until fa4d9c43f enrolled them.
#
# It stays a list rather than a glob because ORDER IS LOAD-BEARING here --
# proto/check.sh and the phase1..phase4 chain are sequenced deliberately -- so
# a glob would be a behaviour change, not a cleanup. If you convert it, keep
# the sequenced prefix explicit and glob only the tail.
#
# ADD YOUR CHECKER HERE IN THE SAME COMMIT THAT ADDS THE FILE.
#
# ...and the block below is what makes that instruction load-bearing instead of
# a comment. It asserts that every check_*.sh in this directory is NAMED in the
# list, so forgetting one is a RED here rather than a silence. That is the same
# discipline the checkers themselves apply to their subjects: assert the thing
# under test actually RAN before believing its output. A suite cannot report a
# row it never reached, so nothing else in the world can catch this.
fail=0

missing=
for f in "$here"/check_*.sh; do
  b=$(basename "$f")
  [ "$b" = "check_all.sh" ] && continue
  # The list lives in the `for c in ...` line below; grep for the exact token.
  grep -q "[ ]$b[ ;]" "$0" || missing="$missing $b"
done
if [ -n "$missing" ]; then
  echo "FAIL these checkers exist in test/wasm/ and are named nowhere in this"
  echo "     file, so they have never run and no result anywhere reports them:"
  for b in $missing; do echo "       $b"; done
  echo "     Add them to the list below. See the note above it."
  exit 1
fi
echo "ok  every check_*.sh in this directory is enrolled in the list"

for c in check_forwards.sh proto/check.sh check_phase1.sh check_phase2.sh check_phase3.sh check_phase4.sh check_data.sh check_calls.sh check_host.sh check_frozen.sh check_exc.sh check_managed.sh check_strop.sh check_index.sh check_dyn.sh check_set.sh check_defmem.sh check_openarr.sh check_aggret.sh check_nested.sh check_fieldlen.sh check_recmgd.sh check_recarr.sh check_scopeexit.sh check_unwindrel.sh check_zeroinit.sh check_pal.sh check_wasi.sh check_argv.sh check_floatint.sh check_floatwrite.sh check_classref.sh check_sysio.sh check_loadfile.sh check_heapgrow.sh check_varparam.sh check_outparam.sh check_intf.sh check_variantptr.sh check_align.sh check_wasidiff.sh check_nilpy_objlocal.sh check_nilpy_generator_slot.sh check_tickets.sh; do
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
