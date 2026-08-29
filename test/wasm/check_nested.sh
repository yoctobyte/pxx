#!/bin/sh
# Nested dynamic arrays on wasm32 — IR_SETLEN_DYN and IR_DYNUNIQUE.
#
# THE ORACLE IS THE NATIVE BUILD, and it has to be, because the failure mode
# here is silence. `SetLength(m, 3)` on an `array of array of Integer` does NOT
# take the flat -102 builtin path: it lowers to IR_SETLEN_DYN whose target is
# an IR_LEA, and IR_LEA on a dynamic array AUTO-LOADS to the data pointer while
# PXXDynSetLen needs the SLOT and treats a nil handle as "nothing to do". The
# first version of this arm did exactly that: every body lowered, the module
# validated, `123 of 123 bodies lowered`, and Length(m) answered 0.
#
# riscv32 shipped that same bug once
# (bug-a-riscv32-nested-dynamic-array-element-write-segfaults), and the -102
# arm carries a paragraph warning about it. Reading the warning was not enough
# to avoid it, because the warning is phrased about WasmLValueAddr-vs-IR_LEA
# and this arm reaches the slot a third way. So the guard is a diff, not a
# comment.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-nested.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/nested_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/nested_slice.pas" "$work/ne.wasm" \
    > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/ne.wasm"

if grep -qE '^    main\$[0-9]' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    main\$[0-9]' "$work/cov.txt"
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
try { inst.exports.main(); } catch (e) { if (!(e instanceof h.HostExit)) throw e; }
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(h.text(1));
JS

node "$work/run.js" "$work/ne.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines)"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# --- each property named, because a diff passes if the wrong rows agree ------
# The FIRST row is the one that caught the real bug and it is not redundant
# with the others: a SetLength that silently does nothing leaves every
# subsequent row reading zeros, which is a consistent and wholly wrong picture.
miss=""
grep -q '^outer len=3$'                       "$work/wasm.txt" || miss="$miss root-setlen-on-a-nested-array"
grep -q '^read  0 12 23$'                     "$work/wasm.txt" || miss="$miss nested-index-read"
grep -q '^ragged len=3 m10=10$'               "$work/wasm.txt" || miss="$miss ragged-rows"
grep -q '^ragged tail=99 neighbour=23$'        "$work/wasm.txt" || miss="$miss ragged-write-no-neighbour-damage"
grep -q '^deep  0 101 111$'                   "$work/wasm.txt" || miss="$miss three-levels"
grep -q '^grow  len=5 kept=0 99$'             "$work/wasm.txt" || miss="$miss grow-preserves-contents"
grep -q '^sum   138$'                         "$work/wasm.txt" || miss="$miss full-traversal"
if [ -n "$miss" ]; then
  echo "FAIL wrong nested dynamic-array behaviour for:$miss"
  cat "$work/wasm.txt"
  exit 1
fi
echo "ok  every property is right, named one by one:"
echo "..  SetLength on an array OF arrays (the row that fails silently);"
echo "..  nested reads; rows of different lengths, and a write to a long row"
echo "..  leaving its neighbour intact; three levels, so IR_DYNUNIQUE recurses"
echo "..  through its own output; and growing the outer array without losing"
echo "..  the rows already in it"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/nested_slice.pas" "$work" ne

# --- what this check does NOT catch -----------------------------------------
# `Length(m[1])` — the length of a nested ROW — still refuses as `Length of
# Pointer`, so it is absent from the slice. Its argument arrives as a bare
# IR_INDEX, whose value is the ADDRESS of the slot holding the inner handle,
# where the root case's IR_LEA yields the handle itself: one deref apart, and
# WasmNodeIsDynArray cannot tell them apart from the node kind alone. Two
# refusal lines in compiler.pas. Everything else about a nested row — writing
# it, reading it, resizing it — is covered above.

echo "PASS check_nested"
