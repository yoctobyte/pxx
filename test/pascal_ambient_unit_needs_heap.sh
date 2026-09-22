#!/bin/sh
# An ambient unit that is Pascal over managed strings must drag builtinheap
# with it -- and a program that pulls NO ambient unit must still pay nothing.
#
# WHAT THIS GUARDS. The Pascal driver decides needHeapUnit early, then goes on
# setting ambient-unit flags (needsBuiltin, needsEntropy, needsEspAssert) for
# another ~550 lines. Those units are ordinary Pascal written over managed
# strings, so pulling one without builtinheap leaves its PXXStr* forwards
# declared and never defined. Live bug, shipped default once the evidence scan
# landed: bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce.
#
# THE TWO ASSERTIONS PULL IN OPPOSITE DIRECTIONS AND BOTH ARE REQUIRED. That
# is the whole design:
#   1. every shape below must BUILD -- catches the union being too narrow;
#   2. an empty program must stay under the proc ceiling -- catches somebody
#      "fixing" a future instance of (1) by widening the union until every
#      program pulls builtinheap again, which is the 63KB hello-world this
#      ticket exists to remove. Without (2) the cheapest repair for (1) is a
#      regression that this file would applaud.
#
# WHY THE SHAPES ARE TYPE DECLARATIONS AND AN Assert. None of them is a string
# and none names one -- that is the point. The trigger is never the string type
# a scan looks for, it is a unit arriving behind an innocent-looking name, so a
# fixture built from string-shaped inputs would pass on the broken compiler.
#
# BOTH ASSERTIONS HAVE A NEGATIVE CONTROL THAT WAS RUN, NOT ASSERTED
# (2026-09-22, frankb-8e). They are different builds, because the two
# assertions fail for opposite reasons and no single build can show both:
#
#   assertion 1: narrow the union in pasparser_prog.inc back to
#     `if needsBuiltin then` and rebuild -> the entropy row and BOTH Assert
#     rows fail with `unresolved forward: PXXStrFromLit` / `PXXStrDecRef`,
#     while `var v: WideChar` keeps building at 592 procs. So these are not
#     several spellings of one row; each arm is load-bearing on its own. The
#     narrowed build reproduced binary sha e36d1600de4c EXACTLY and restoring
#     reproduced 8b2a3da93d27, so the control measured the same tree rather
#     than a similar one.
#
#   assertion 2: run this script against $(PXX_STABLE) -- the pinned compiler
#     defines PXX_MANAGED_STRING unconditionally, so every row builds and the
#     empty program reports 149 procs against the ceiling of 80. It exits 1
#     on exactly the row it is supposed to.
#
# TAKES THE BUILT COMPILER, NOT $(PXX_STABLE): the fix is a compiler change and
# is inert in the pin until a pin carries it, so wired to the pinned binary
# this would be RED today for the right reason and GREEN later for the wrong
# one.
#
# Usage: sh test/pascal_ambient_unit_needs_heap.sh <pxx> <tmpdir>
set -e
PXX=${1:?usage: pascal_ambient_unit_needs_heap.sh <pxx> <tmpdir>}
TMP=${2:?usage: pascal_ambient_unit_needs_heap.sh <pxx> <tmpdir>}

fail=0

# --- assertion 1: each ambient-unit trigger must still build ---------------
try() {
  label=$1; src=$2; shift 2
  printf 'program t;\n%s\n' "$src" > "$TMP/amb.pas"
  if out=$("$PXX" "$@" "$TMP/amb.pas" "$TMP/amb.bin" 2>&1); then
    :
  else
    echo "FAIL: $label did not build."
    echo "$out" | tail -3
    fail=$((fail + 1))
    return
  fi
  case $out in
    *"unresolved forward"*)
      echo "FAIL: $label built with an unresolved forward:"
      echo "$out" | grep 'unresolved forward' | head -1
      fail=$((fail + 1)) ;;
  esac
}

try "var v: WideChar"  'var v: WideChar;
begin Halt(0); end.'
try "var v: PChar"     'var v: PChar;
begin Halt(0); end.'
try "var v: UCS4Char"  'var v: UCS4Char;
begin Halt(0); end.'
try "__pxxHwRandom64"  'var v: UInt64;
begin if __pxxHwRandom64(v) then Halt(0); end.'
try "Assert/bare xtensa"  'begin Assert(1 = 1); Halt(0); end.' \
    --target=xtensa --esp-profile=bare
try "Assert/bare riscv32" 'begin Assert(1 = 1); Halt(0); end.' \
    --target=riscv32 --esp-profile=bare

# The same class reached WITHOUT pulling an ambient unit: emitted code calling
# a builtinheap helper directly. Found by a 2312-file compile-only differential
# against the pinned compiler, not by reading -- all three were live failures
# the six rows above did not cover.
#   :w:d  -> PXXWriteFloatFixed   (test_cross_aggregate_stackargs.pas:57)
#   {$Q+} -> PXXOverflow          (test_qplus_narrowing_store.pas,
#                                  test_qplus_survives_ambient_units.pas)
# The float row carries NO float literal and no `/`, which is exactly why the
# tkFloat/tkSlash arms of the scan cannot see it.
try "writeln :0:0 format"  'var d: Double;
begin d := 1; writeln(d:0:0); Halt(0); end.'
try "{\$Q+} overflow check" '{$Q+}
var a, b: Integer;
begin a := 2; b := 3; a := a * b; if a = 6 then Halt(0); end.'

# --- assertion 2: the saving must survive ----------------------------------
# An empty program pulls no ambient unit and must stay tiny. The ceiling is
# deliberately loose (the measured value is 37; the pre-fix unconditional
# behaviour was 149) so ordinary drift does not redden it, while the failure
# this guards -- every program pulling builtinheap again -- lands far outside.
CEIL=80
printf 'program e;\nbegin\nend.\n' > "$TMP/amb_empty.pas"
out=$("$PXX" "$TMP/amb_empty.pas" "$TMP/amb_empty.bin" 2>&1) || {
  echo "FAIL: the empty program did not build."; echo "$out" | tail -3; exit 1; }
procs=$(echo "$out" | sed -n 's/.*procs=\([0-9]*\).*/\1/p' | head -1)
if [ -z "$procs" ]; then
  echo "FAIL: could not read procs= from the ok line -- has its format changed?"
  echo "$out" | tail -2
  fail=$((fail + 1))
elif [ "$procs" -gt "$CEIL" ]; then
  echo "FAIL: an empty program emits $procs procs, over the ceiling of $CEIL."
  echo "      Something made every Pascal program pull an ambient unit again."
  echo "      Widening the needHeapUnit union until assertion 1 passes is the"
  echo "      way this happens; fix the specific trigger instead."
  fail=$((fail + 1))
fi

[ "$fail" -eq 0 ] || exit 1
echo "  test: ambient units drag builtinheap; empty stays $procs procs (ceiling $CEIL)"
