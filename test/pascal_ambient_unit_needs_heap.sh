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

# A RECORD USED AS A VALUE, on a target whose aggregate epilogue lowers a
# whole-record copy onto builtinheap's PXXMemMove. Live break shipped by the
# evidence scan, reported by frankh-c0 2026-09-22 and reproduced on riscv32,
# xtensa, arm32 and aarch64 -- the set TargetCodegenCallsHeapRuntime owns.
#
# FOUR ROWS BECAUSE THE DEFECT HAS FOUR SHAPES AND THE REPORT HAD ONE. It was
# reduced to "a function whose RESULT TYPE is a record", which is a syntactic
# corner, and the proposed repair matched that construct. Varying the shape
# first is the only reason the other three were found: whole-record
# assignment, a record PARAMETER by value, and assignment from a typed const
# all break identically, and a rule aimed at the function result would have
# fixed a quarter of it and closed the ticket. Field-only use is the single
# shape that builds and it is NOT a row here -- it is the thing assertion 3
# below protects.
#
# THE `object` ROW IS NOT A SPELLING VARIANT, IT IS A DIFFERENT TOKEN KIND.
# `record` lexes as tkRecord; `object` lexes as an ordinary tkIdent, so a
# scan written against the kind alone misses `TB = object ... end` completely
# while passing every row above it. Same trap as `string`/tkString_T, in a
# second keyword, and a fixture without this row certifies the half that works.
try "record: whole-copy"   'type TB = record a, b, c: Integer; end;
var r, q: TB;
begin q.a := 7; r := q; if r.a = 0 then Halt(1); Halt(0); end.' \
    --target=riscv32 --platform=posix
try "record: param by value" 'type TB = record a, b, c: Integer; end;
procedure F(v: TB); begin if v.a = 0 then Halt(1); end;
var r: TB;
begin r.a := 7; F(r); Halt(0); end.' \
    --target=riscv32 --platform=posix
try "record: function result" 'type TB = record a, b, c: Integer; end;
function M(x: Integer): TB; begin M.a := x; M.b := x; M.c := x; end;
var r: TB;
begin r := M(7); if r.a = 0 then Halt(1); Halt(0); end.' \
    --target=riscv32 --platform=posix
try "record: from typed const" 'type TB = record a, b, c: Integer; end;
const K: TB = (a: 1; b: 2; c: 3);
var r: TB;
begin r := K; if r.a = 0 then Halt(1); Halt(0); end.' \
    --target=riscv32 --platform=posix
try "object: whole-copy"   'type TB = object a, b, c: Integer; end;
var r, q: TB;
begin q.a := 7; r := q; if r.a = 0 then Halt(1); Halt(0); end.' \
    --target=riscv32 --platform=posix

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

# --- assertion 3: the record arm must stay TARGET-GATED --------------------
# Assertion 2 cannot see this one: its subject is an EMPTY program, which has
# no record in it, so ungating the record trigger to every target leaves it
# green. The record rows above pull in the opposite direction and would also
# stay green -- widening the arm is the cheapest way to make them pass. This is
# the row that makes that repair visible.
#
# x86-64 and i386 copy a record inline and call nothing, measured: the same
# source is 38 procs here and 185 on riscv32, where the unit is genuinely
# needed. The ceiling is the same loose 80 as assertion 2 for the same reason.
#
# THE COST THIS PROTECTS IS x86-64 SIZE, AND THE BARE-ESP HALF OF THIS NOTE WAS
# TRUE FOR ONE HOUR. Written 2026-09-22 as: on --esp-profile=bare builtinheap
# brings a 65,536 B EspArena, so a bare esp32c3 program that declares a record
# and only touches its FIELDS goes bss 652 -> 66,824 B under the arm above.
# That was measured and correct at binary 81bf5f94fb6f. frankh-c0's 04e20af2c
# landed the same hour and drops the arena when DCE proves HeapMmap dead, and
# re-measuring the IDENTICAL program at 8c22736b1a7d gives bss 652 -> 1,288 B,
# with and without --dce. The difference is 65,536 exactly, so the attribution
# is not a guess. Over-detection here now costs ~636 B, not ~66 KB.
#
# KEPT RATHER THAN OVERWRITTEN because the author of that commit told me in the
# same message that it "does not help your case, because your trigger pulls
# builtinheap and keeps the allocator reachable" -- a reasonable reading of
# one's own change, and measurably wrong. Neither of us would have caught it by
# reading. Carry both rows with their binaries rather than replacing one with
# the other.
#
# The arm above is still accepted for the reason it always was -- the
# alternative is a build break on four targets -- and the real repair is still
# feature-a-pull-builtinheap-on-demand-instead-of-predicting-it. Do not read
# this assertion as blessing any arena; it only stops the x86-64 cost.
printf 'program r;\ntype TB = record a, b, c: Integer; end;\nvar r, q: TB;\nbegin q.a := 7; r := q; if r.a = 0 then Halt(1); end.\n' > "$TMP/amb_rec.pas"
out=$("$PXX" "$TMP/amb_rec.pas" "$TMP/amb_rec.bin" 2>&1) || {
  echo "FAIL: the x86-64 record program did not build."; echo "$out" | tail -3; exit 1; }
recprocs=$(echo "$out" | sed -n 's/.*procs=\([0-9]*\).*/\1/p' | head -1)
if [ -z "$recprocs" ]; then
  echo "FAIL: could not read procs= from the record program's ok line."
  echo "$out" | tail -2
  fail=$((fail + 1))
elif [ "$recprocs" -gt "$CEIL" ]; then
  echo "FAIL: an x86-64 record program emits $recprocs procs, over $CEIL."
  echo "      The record trigger in DetectPascalRuntimeNeeds has lost its"
  echo "      TargetCodegenCallsHeapRuntime gate, so every target now pays for"
  echo "      a copy x86-64 and i386 do inline. Re-gate it; do not raise CEIL."
  fail=$((fail + 1))
fi

[ "$fail" -eq 0 ] || exit 1
echo "  test: ambient units drag builtinheap; empty stays $procs procs, x86-64 record $recprocs (ceiling $CEIL)"
