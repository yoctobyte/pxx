#!/bin/sh
# `Length` of a dynamic array held in a SLOT — a record/class field, or an
# element of a static array of rows.
#
# THE ORACLE IS THE NATIVE BUILD, and for this arm the diff is close to the
# whole instrument: every way a wrong deref depth can go wrong is a wrong
# NUMBER, and the numbers here are all distinct on purpose (5 2 / 4 5 6 / 3 6 /
# 3 1 3 5) so that an arm reading one row's count for another's is a visible
# disagreement rather than a coincidence.
#
# The one thing a diff of counts cannot see is a right count over a wrong data
# pointer, so the slice also reads elements back and prints a string field.
#
# WHY THIS SHAPE HAD BEEN REFUSED. The node's IR type is `Pointer`, so this
# target's message read `Length of Pointer` — which was never about pointers.
# The refusal named the type of a node it did not recognise, and the type it
# named is the one x86-64 uses as its DISCRIMINATOR for exactly this arm. A
# diagnostic that names a cause does your reasoning for you, and here it did it
# wrongly for as long as the arm was missing.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-fieldlen.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/fieldlen_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/fieldlen_slice.pas" \
    "$work/s.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/s.wasm"

if grep -qE '^    (Show|main\$0) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Show|main\$0) ' "$work/cov.txt"
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

node "$work/run.js" "$work/s.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines)"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# --- per-row, because a whole-file diff names the file and not the shape -----
for row in \
  'rec     5 2' \
  'nilrec  0 0' \
  'varrec  5 2' \
  'cstrec  5 2' \
  'grid    4 5 6' \
  'vargrid 4 5 6' \
  'nilcls  0' \
  'cls     9' \
  'idxfld  3 6' \
  'nested  3 1 3 5' \
  'grown   11' \
  'emptied 0' \
  'read    0 30 50' \
  'strs    alpha beta'
do
  grep -qxF "$row" "$work/wasm.txt" || {
    echo "FAIL missing row: $row"; exit 1; }
done
echo "ok  every row asserted individually:"
echo "..  record field as a local, a var param and a const param, a class"
echo "..  field, a static array of rows read directly and through a var param,"
echo "..  a field reached through an index, a nested row, grow and empty"
echo "..  through the field, nil for both a never-SetLength record field and a"
echo "..  fresh object's, and the data read back so a right count over a wrong"
echo "..  pointer cannot pass"

# --- both node kinds, asserted rather than assumed ---------------------------
# The arm keys off IR_FIELD *or* IR_INDEX, and a slice that routed every case
# through one of them would look like coverage and be half of one. P1 and P2
# exist in the slice for no other reason, and this is where that claim is
# checked instead of stated in a comment.
for pr in ShowVarGrid ShowVarRec; do
  PXXDBG="a.ir:$pr" "$root/compiler/pascal26" --target=wasm32 \
      "$here/fieldlen_slice.pas" "$work/x.wasm" > "$work/ir.$pr" 2>&1 || true
done
if ! grep -qE '^[0-9]+: index .* tk=17' "$work/ir.ShowVarGrid"; then
  echo "FAIL ShowVarGrid no longer lowers through an IR_INDEX of pointer type,"
  echo "     so the IR_INDEX half of the Length arm is untested by this slice."
  exit 1
fi
if ! grep -qE '^[0-9]+: field .* tk=17' "$work/ir.ShowVarRec"; then
  echo "FAIL ShowVarRec no longer lowers through an IR_FIELD of pointer type,"
  echo "     so the IR_FIELD half of the Length arm is untested by this slice."
  exit 1
fi
echo "ok  both halves of the arm are reached: ShowVarGrid through IR_INDEX and"
echo "..  ShowVarRec through IR_FIELD, both typed Pointer — measured in the IR,"
echo "..  not inferred from the source looking different"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/fieldlen_slice.pas" \
   "$work" s

# --- what this check does NOT catch -----------------------------------------
#  * Length of a field of a field (`a.b.Bytes`) — a deeper FIELD nest. The arm
#    does not care how the address was computed, but that is an argument, not a
#    measurement, and it is not measured here.
#  * SetLength through a field of an INDEXED record (`bs[0].Bytes`) is written
#    above, but only its resulting Length is asserted; the write path is
#    check_nested's subject.
#  * a dyn-array field of a RECORD RETURNED BY VALUE from a function — the
#    aggregate-result arm and this one meeting, which nothing exercises yet.
#  * anything about WideString or a frozen-string field: the slot arm is typed
#    on tyPointer and those are not.
#  * a record passed BY VALUE. Removed from the slice rather than left to fail:
#    it refuses with `statement IR op 46` (IR_COPY_REC_MANAGED), which is the
#    separate feature of copying a record that owns managed fields. The var and
#    const forms cover this arm; the by-value one covers that one.
echo "PASS check_fieldlen"
