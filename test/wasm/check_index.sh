#!/bin/sh
# Indexing a managed string, and SetLength — wasm32.
#
# These two arrive together because they are one question asked from opposite
# ends: both need the SLOT's address, so that PXXStrUnique (copy-on-write) or
# PXXStrSetLen can publish a NEW handle into it. Everything before slice 3
# reached a managed string in read position only, where the slot's contents —
# the handle — is the answer; these are the shapes where it is not.
#
# The failure mode is why this script exists. A write that uses the handle
# where the slot address belongs does not crash at the store: it puts one
# character (or, for SetLength, a whole heap pointer) over the first bytes of
# the string's own characters. The string then reads back short or malformed
# and the program keeps going until scope exit tries to release it. So the
# oracle is the NATIVE build and the diff is the primary assertion.
#
# Three things the diff alone would not pin, each measured by deliberately
# breaking the compiler and watching this slice go red:
#
#   * COW. `t := s; s[1] := 'X'` must leave t alone. Skipping PXXStrUnique
#     edits the shared block, and ONLY the two aliasing lines of the slice
#     catch it — every other line passes. Verified by removing the call.
#   * The write arm of IR_LEA. Answering HANDLE in write position makes this
#     slice TRAP, not diverge. Verified by restoring the old unconditional
#     load.
#   * The index sub-expression is a READ inside a write. `s[Length(s)] := '!'`
#     evaluates Length against the base; with the write flag left set, Length
#     reads the slot instead and the store lands nowhere. Verified by removing
#     the reset — `a?c!` became `abcd`, one line, silently.
#
# And the position model itself, asserted positively rather than through a list
# of what refuses. That list is what this check replaces: check_managed.sh used
# to assert that SetLength and indexed writes still REFUSED, because IR_LEA
# answered handle unconditionally and that is sound only while no write can
# reach it. Slice 3 made both lower, so that check went red on a correct
# change — by design. The argument was replaced rather than the list trimmed:
# the position is now modelled with InLValueWrite, and what is asserted here is
# that the two positions produce DIFFERENT code.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-index.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/index_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 \
    "$here/index_slice.pas" "$work/i.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/i.wasm"

# The positive twin of every negative below.
if grep -qE '^    (FillVar|ReadVar|Reverse|main\$0) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (FillVar|ReadVar|Reverse|main\$0) ' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
const sp0 = inst.exports.sp.value;
try { inst.exports.main(); }
catch (e) { if (!(e instanceof h.HostExit)) throw e; }
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(h.text());
JS

node "$work/run.js" "$work/i.wasm" > "$work/wasm.txt"
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  read and write on a scalar, a record field, an array element and a"
  echo "..  var parameter; constant and variable indices; COW single-shot and"
  echo "..  in a loop; SetLength grow / shrink / to zero / on a shared string;"
  echo "..  a managed function result written through by index; \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# --- the position model, both halves ----------------------------------------
# Two programs differing only in which side of the assignment `s[1]` is on.
# The write must clone-if-shared; the read must not. A model that collapsed to
# "always read" traps (measured); one that collapsed to "always write" gives
# the right characters and merely clones needlessly, so the read half here is
# the one a diff can never make.
pos() {   # $1 = body -> prints how many times main$0 calls PXXStrUnique
  cat > "$work/pos.pas" <<EOF
program P;
var s: string; c: Char;
begin
  s := 'abc';
$1
  writeln(s, c);
end.
EOF
  "$root/compiler/pascal26" --target=wasm32 "$work/pos.pas" "$work/pos.wat" \
      > /dev/null 2>&1
  awk '/\(func \$main\$0/,/^  \)/' "$work/pos.wat" | grep -c 'call \$PXXStrUnique' || true
}
r=$(pos "  c := s[1];")
w=$(pos "  s[1] := 'z';")
if [ "$r" != "0" ] || [ "$w" != "1" ]; then
  echo "FAIL the position model does not distinguish read from write:"
  echo "     reading s[1] calls PXXStrUnique $r times (want 0)"
  echo "     writing s[1] calls PXXStrUnique $w times (want 1)"
  exit 1
fi
echo "ok  read position hands back the handle; write position clones-if-shared"
echo "..  — the same source, one line apart, emits different code"

# SetLength must go through PXXStrSetLen. A store that produced the right
# characters without it — clamping a length word, say — would pass the diff on
# a slice this short and corrupt anything longer.
#
# What is NOT asserted here, and the reason is worth more than the assertion
# would have been: the first version of this block also grepped for an
# `i32.load` before the call, meaning to catch SetLength being handed the
# HANDLE where the slot address belongs. That check was vacuous and wrong. A
# global's slot address is an `i32.const` and a local's is fp+N, so no load
# appears in either shape and the grep asserted nothing — while a `var s:
# string` parameter's slot address legitimately IS a load, so the day one
# reached this grep it would have failed on correct code. The property is real
# and the diff already carries it: handing PXXStrSetLen the handle makes it
# read the string's first four characters as a pointer, and this slice then
# produces NO output at all (measured). Passing on first write is not evidence
# that an assertion is quantified over the right thing.
cat > "$work/sl.pas" <<'EOF'
program S;
var s: string;
begin
  s := 'abc';
  SetLength(s, 2);
  writeln(s);
end.
EOF
"$root/compiler/pascal26" --target=wasm32 "$work/sl.pas" "$work/sl.wat" >/dev/null 2>&1
if ! awk '/\(func \$main\$0/,/^  \)/' "$work/sl.wat" | grep -q 'call \$PXXStrSetLen'; then
  echo "FAIL SetLength on a managed string does not call PXXStrSetLen"
  exit 1
fi
echo "ok  SetLength lowers to PXXStrSetLen, not to a length-word store"

# --- the leak probe ---------------------------------------------------------
# Same shape as check_strop's, and for the same reason: a diff cannot see a
# refcount. COW allocates a clone and must release the original; SetLength
# allocates a fresh block and must release the old. Both are invisible in
# output and both are one missing DecRef away from a leak.
#
# 1024 bytes is a size the loop never allocates and so never frees, which makes
# every probe call bump the arena rather than pop a free list. Taking the
# advance at TWO iteration counts is what separates the constant term from the
# per-iteration one — the single-count form reads as agreement with whatever
# the other build does, which in slice 2 was a build that leaked.
mkleak() { cat > "$work/leak.pas" <<EOF
program Leak;
var i: Integer; s, t: string; p1, p2: Pointer;
begin
  for i := 1 to 100 do
  begin
    s := 'shared-string'; t := s; s[1] := 'X';
    SetLength(s, 4); SetLength(t, 20); t[20] := 'z';
  end;
  p1 := PXXAlloc(1024, 8);
  for i := 1 to $1 do
  begin
    s := 'shared-string'; t := s; s[1] := 'X';
    SetLength(s, 4); SetLength(t, 20); t[20] := 'z';
  end;
  p2 := PXXAlloc(1024, 8);
  writeln(NativeInt(p2) - NativeInt(p1));
end.
EOF
}
leakrun() {
  mkleak "$1"
  "$root/compiler/pascal26" --target=wasm32 "$work/leak.pas" "$work/leak.wasm" \
      > /dev/null 2>&1
  node "$work/run.js" "$work/leak.wasm"
}
a1=$(leakrun 1000)
a2=$(leakrun 9000)
if [ "$a1" != "$a2" ]; then
  echo "FAIL a COW clone or a SetLength block is leaked: 1000 iterations"
  echo "     advance the heap by $a1 bytes and 9000 by $a2 — a build that"
  echo "     released everything gives the same number at both counts"
  exit 1
fi
echo "ok  1000 and 9000 iterations both advance the heap by $a1 bytes — the"
echo "..  COW original and the pre-SetLength block are both released"

# The native build agrees here, and that is worth recording rather than
# assuming: slice 2 found the x86-64 build leaking an owned string operand in a
# comparison (bug-a-a-string-function-result-in-a-comparison-leaks-on-x86-64),
# so "the reference does the same thing" is not by itself evidence of anything.
# It is evidence here only because BOTH slopes are zero, which is a property,
# not an agreement.
mkleak 1000
"$root/compiler/pascal26" "$work/leak.pas" "$work/leakn" > /dev/null
n1=$("$work/leakn")
mkleak 9000
"$root/compiler/pascal26" "$work/leak.pas" "$work/leakn" > /dev/null
n2=$("$work/leakn")
if [ "$n1" != "$n2" ]; then
  echo "FAIL the NATIVE build leaks across these shapes ($n1 -> $n2) — that is"
  echo "     an x86-64 bug and wants its own ticket, not a change here"
  exit 1
fi
echo "ok  the native build's slope is zero too ($n1 bytes at both counts) —"
echo "..  two independent builds, each leaking nothing, not two agreeing"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/index_slice.pas" "$work" i

echo "PASS check_index"
