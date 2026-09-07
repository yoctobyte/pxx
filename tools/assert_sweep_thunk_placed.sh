#!/bin/sh
# Assert that an out-of-line managed-sweep THUNK was actually placed in <proc>.
#
# Why this exists: test_sweep_thunk_preserves_stack_alignment asserts that every
# destructor call in one body saw the same frame alignment (min = max). That is
# the right RELATION, but it is only a test OF THE THUNK while a thunk is being
# placed. If the slot threshold ever moves, every return inlines its sweep, the
# residues agree trivially and the row prints ALIGN OK for a reason that has
# nothing to do with the constant it exists to guard. Assert the precondition,
# not just the comparison.
#
# The tell carries no per-target constant. Inside the body:
#   thunk epilogue    : add rsp, N ; ret     (N = 8 on x86-64, 12 on i386)
#   procedure return  : leave      ; ret
# so "a ret reached over an rsp adjustment rather than over leave" is the thunk,
# on any target that gets one.
#
# usage: assert_sweep_thunk_placed.sh <file.s> <proc> present|absent
set -e
asm=$1; proc=$2; want=$3
[ -f "$asm" ] || { echo "assert_sweep_thunk_placed: no such assembly: $asm"; exit 1; }
# The label must EXIST. Without this, `absent` passes vacuously for a procedure
# that was renamed or removed -- a control certifying a subject that is gone.
grep -qE "^$proc:[ \t]*$" "$asm" || {
  echo "assert_sweep_thunk_placed: FAIL — no procedure '$proc' in $asm."
  echo "  The row names a procedure the compiler did not emit; it cannot be a"
  echo "  control for anything. Renamed, or never compiled."
  exit 1
}
n=$(awk -v p="$proc:" '
  $0 ~ "^"p         { inb=1; next }
  inb && /^[^ \t].*:[ \t]*$/ { inb=0 }
  inb {
    line=$0; sub(/^[ \t]+/,"",line); sub(/[ \t]+$/,"",line)
    if (line == "ret" && prev ~ /^add (rsp|esp),/) n++
    if (line != "") prev=line
  }
  END { print n+0 }
' "$asm")
case "$want" in
  present)
    if [ "$n" -ge 1 ]; then
      echo "sweep-thunk-placed: OK ($proc has $n thunk epilogue(s))"
    else
      echo "sweep-thunk-placed: FAIL — no thunk in $proc, so the alignment row"
      echo "  compared inline sweeps against inline sweeps and could not fail."
      exit 1
    fi ;;
  absent)
    if [ "$n" -eq 0 ]; then
      echo "sweep-thunk-placed: OK (control: $proc has no thunk, as expected)"
    else
      echo "sweep-thunk-placed: FAIL — control procedure $proc grew $n thunk"
      echo "  epilogue(s); the detector no longer discriminates."
      exit 1
    fi ;;
  *) echo "usage: $0 <file.s> <proc> present|absent"; exit 2 ;;
esac
