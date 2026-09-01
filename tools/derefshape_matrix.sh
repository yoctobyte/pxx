#!/bin/sh
# Per-shape x per-arm control for `p^[i]`: the two deref walks
# (NodePtrElem and ResolveDerefShapeAt) are documented as neither being a
# superset of the other -- ResolveDerefShape richer per shape, NodePtrElem
# richer in shapes -- so a change that swaps a call site from one to the other
# can regress in two INDEPENDENT directions and a green `make test` sees
# neither. That is not hypothetical: 15ec54d7a shipped exactly that way and was
# fixed in bfb7b4c59.
#
# So the unit here is a ROW = (how the pointer is spelled) x (what the element
# is), not a program. Every row writes the same values through a different
# spelling and reads them back through the plain array, so a row's expected
# output does not depend on the walk being tested.
#
# THE PLAIN ROWS ARE THE POSITIVE CONTROL and must always pass: same
# arithmetic, same element kind, the one spelling that works today. If a plain
# row fails, the harness is measuring a broken build and every other verdict on
# the run is void -- so that is checked FIRST and aborts.
#
# Rows are separate PROGRAMS because four faces currently SEGV or HANG, and a
# single program cannot survive one to report the rest.
#
# Usage: tools/derefshape_matrix.sh [compiler]   (default compiler/pascal26)
set -u
PXX="${1:-compiler/pascal26}"
D=test/derefshape
OUT="${TMPDIR:-/tmp}/derefshape.$$"
mkdir -p "$OUT" || exit 2
[ -x "$PXX" ] || { echo "derefshape: no compiler at $PXX"; exit 2; }
[ -f "$D/EXPECTED" ] || { echo "derefshape: no $D/EXPECTED"; exit 2; }

run_row() {  # $1 = name, $2 = expected -> echoes the verdict word
  n=$1; exp=$2
  if ! "$PXX" -O2 "$D/$n.pas" "$OUT/$n" >"$OUT/$n.ce" 2>&1; then
    echo "COMPILE-ERROR"; return
  fi
  # The subshell keeps the SHELL's own "Segmentation fault (core dumped)"
  # reaping message out of the report: it is written by the parent shell, not
  # by the program, so redirecting the program's stderr alone does not stop it.
  got=$( { timeout 10 "$OUT/$n"; } 2>/dev/null ); rc=$?
  if [ $rc -eq 124 ]; then echo "HANG"
  elif [ $rc -ge 128 ]; then echo "SIGNAL-$rc"
  elif [ $rc -ne 0 ]; then echo "EXIT-$rc"
  elif [ "$got" = "$exp" ]; then echo "ok"
  else echo "WRONG[$got]"
  fi
}

# --- positive control first: a broken build must not be reported as findings ---
ctl_bad=0
while read -r n exp; do
  case "$n" in ds_plain_*) ;; *) continue ;; esac
  v=$(run_row "$n" "$exp")
  [ "$v" = "ok" ] || { echo "CONTROL FAILED: $n -> $v (expected '$exp')"; ctl_bad=1; }
done < "$D/EXPECTED"
if [ $ctl_bad -ne 0 ]; then
  echo "derefshape: the plain-identifier control rows do not pass, so this build"
  echo "derefshape: cannot measure anything. No row verdicts are reported."
  rm -rf "$OUT"; exit 2
fi

fail=0; nrow=0
while read -r n exp; do
  nrow=$((nrow + 1))
  v=$(run_row "$n" "$exp")
  printf '%-26s %s\n' "$n" "$v"
  [ "$v" = "ok" ] || fail=$((fail + 1))
done < "$D/EXPECTED"
echo "derefshape: $nrow rows, $fail failing (control rows passed)"
rm -rf "$OUT"
[ $fail -eq 0 ] || exit 1
