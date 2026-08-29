#!/bin/sh
# A dynamic ARRAY OF RECORDS on wasm32 — `a[i].Field`, the growable
# array-of-structs shape.
#
# THE ORACLE IS THE NATIVE BUILD, and the numbers in the slice are chosen so a
# stride error is a visible disagreement rather than a coincidence: elements
# hold Off = 10, 20, ... 90 with W = 1..9, so reading one element short or long
# lands on a value that is obviously the neighbour's. An 8-byte record indexed
# with a 4-byte stride would read 10, 1, 20, 2 — and it is exactly that class of
# bug the diff cannot mistake for anything else.
#
# The managed-field rows are a second stride witness that does not depend on
# the numbers at all: a record containing a string is still strided by the whole
# record, and a stride taken from the HANDLE instead would put two names on top
# of each other.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-recarr.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/recarr_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/recarr_slice.pas" \
    "$work/s.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/s.wasm"

if grep -qE '^    (Add|BumpVar|main\$0) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Add|BumpVar|main\$0) ' "$work/cov.txt"
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

for row in \
  'count  9 TRUE' \
  'read   10 50 9' \
  'kept   10 4' \
  'comp   70' \
  'copy   999 6 60' \
  'varel  130' \
  'named  alpha beta gamma 3' \
  'rewrit alpha BETA gamma' \
  'sum    49'
do
  grep -qxF "$row" "$work/wasm.txt" || { echo "FAIL missing row: $row"; exit 1; }
done
echo "ok  every row asserted individually:"
echo "..  grow-on-demand writes through the index, growth preserving what was"
echo "..  already written, a computed index, an element read out and written"
echo "..  back as a whole record, an element passed as a var parameter, and an"
echo "..  array of records with a managed field rewritten in place"

# --- the base is an i32, asserted where the refusal used to be ---------------
# The whole fix is that an IR_DYNUNIQUE node's type kind names the ELEMENT and
# its value is a pointer. If the frontend ever stops emitting DYNUNIQUE for this
# shape, the exemption in WasmEmitValueAs goes quiet and the arm is untested
# while the slice still passes through some other route. This says which route.
PXXDBG='a.ir:Add' "$root/compiler/pascal26" --target=wasm32 \
    "$here/recarr_slice.pas" "$work/x.wasm" > "$work/ir.Add" 2>&1 || true
if ! grep -qE '^[0-9]+: dynunique .* tk=5' "$work/ir.Add"; then
  echo "FAIL Add no longer lowers its element write through a record-typed"
  echo "     IR_DYNUNIQUE, so the exemption this check exists for is not the"
  echo "     thing being exercised. Got:"
  grep -E '^[0-9]+: dynunique' "$work/ir.Add" | head -3
  exit 1
fi
echo "ok  the element write really does go through a record-typed IR_DYNUNIQUE"
echo "..  (tk=5), which is the node the refusal named and the exemption clears"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/recarr_slice.pas" \
   "$work" s

# --- what this check does NOT catch -----------------------------------------
#  * a FIXED array of records (`array[0..3] of TRec`). Its base is not a
#    DYNUNIQUE at all, so it never reached this refusal and is not covered by
#    this fix — check_index.sh's territory, and untested for record elements.
#  * an array of records nested two levels (`array of array of TRec`).
#  * a record element containing a dynamic array field, where SetLength writes
#    through a slot inside a heap element.
#  * an array of records with an INTERFACE field: the same untested half of the
#    ARC walk check_recmgd names.
echo "PASS check_recarr"
