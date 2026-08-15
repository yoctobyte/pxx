#!/bin/bash
# Namespace-leak sweep: compile every source in the tree and report ONLY the
# failures that look like a name reached through an import's import.
#
# Why this is not "just run the test suite": the suite RUNS things, needs
# expectations, X11, network, minutes of wall clock, and it is Track T's to
# schedule. This asks one question instead — does every source still RESOLVE
# its names — which is compile-only, embarrassingly parallel, and finishes in
# well under a minute. It exists because the non-transitive-uses change
# (1a32de34b) is invisible to `gate.sh quick` by construction: nothing in the
# quick tier imports deeply enough to leak, so the pusher's gate cannot see the
# one thing this change can break.
#
# Signature it looks for, in the compiler's own words:
#     undefined variable (X)      unknown type: X
#     undefined function (X)      unknown exception class
# The fix for a real hit is ALWAYS the missing `uses` clause in the source that
# named it, never a compiler change — see
# devdocs/progress/done/bug-pascal-uses-non-transitivity-only-covers-routines-and-types.md
#
# Usage:  tools/uses_sweep.sh [dir ...]        (default: test examples lib)
#         tools/uses_sweep.sh --all-errors     (report every failure, not just
#                                               the leak signature — use when
#                                               you want the raw picture)
set -u
cd "$(dirname "$0")/.." || exit 1

COMPILER=${COMPILER:-./compiler/pascal26}
[ -x "$COMPILER" ] || { echo "no compiler at $COMPILER — run make compiler/pascal26" >&2; exit 2; }

ALL=0
if [ "${1:-}" = "--all-errors" ]; then ALL=1; shift; fi
DIRS=("$@")
[ ${#DIRS[@]} -eq 0 ] && DIRS=(test examples lib)

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

# A unit is not compilable on its own and a fixture may be deliberately broken;
# both answer "this file is a unit, not a program" or live under a fixture dir,
# and neither is signal. Everything else is a candidate.
list_sources() {
  for d in "${DIRS[@]}"; do
    [ -d "$d" ] || continue
    find "$d" -type f \( -name '*.pas' -o -name '*.npy' \) \
         -not -path '*/historic/*' -not -path '*/nilpy_units/*' 2>/dev/null
  done
}

compile_one() {
  src="$1"; out="$2"
  err=$("$COMPILER" -Futest "$src" "$out/$(echo "$src" | tr / _).bin" 2>&1 >/dev/null)
  [ -z "$err" ] && return 0
  # not signal: a unit compiled as a program, or a test that is MEANT to fail
  case "$err" in
    *"is a unit, not a program"*) return 0 ;;
  esac
  first=$(echo "$err" | head -1)
  case "$first" in
    *"undefined variable"*|*"undefined function"*|*"unknown type:"*|*"unknown exception class"*)
      echo "LEAK?  $src :: $first" ;;
    *) [ "$ALL" = 1 ] && echo "other  $src :: $first" ;;
  esac
  return 0
}
export -f compile_one
export COMPILER ALL

echo "sweeping: ${DIRS[*]}"
list_sources | sort | xargs -P "$(nproc)" -I{} bash -c 'compile_one "$@"' _ {} "$OUT" \
  | sort | tee "$OUT/hits"

n=$(grep -c 'LEAK?' "$OUT/hits" 2>/dev/null || echo 0)
echo "---"
echo "leak-signature failures: $n"
[ "$n" -eq 0 ] && exit 0 || exit 1
