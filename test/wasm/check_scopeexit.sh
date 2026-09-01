#!/bin/sh
# Managed locals must be released at ORDINARY scope exit on wasm32.
#
# NOT the unwind case and not the assignment case. This is the plain path: a
# procedure returns normally and everything its frame owned has to be released
# on the way out. wasm32 released two managed kinds and silently leaked the
# rest, because its release pass carried a hand-written list of kinds while the
# zero-init pass beside it asked the shared table.
#
# THE HARD PART IS THAT A LEAK PRINTS NOTHING. Both sides of a native-vs-wasm
# differential produce identical OUTPUT while one of them leaks every record it
# touches, so the diff below — which is the primary assertion in every other
# check here — cannot see this defect at all. Measured on the pre-fix backend:
#
#     COM interface local         gone=0 of 50       PXXIntfRelease never called
#     record with managed fields  live=543 of 3799   PXXRecordRelease absent
#     static array of AnsiString  live=871 of 6088   PXXArrayReleaseImmediate absent
#
# So the slice makes the leak PRINT. The object counts its own destructions and
# the program compares that count to the number it made, which turns "released
# or not" into a line of stdout that the diff and the exit status both see. That
# is why the interface row is the one asserted here: it is the only one of the
# three whose failure is observable without -dPXX_ALLOC_CENSUS.
#
# Verified to fail: against the backend one commit earlier this prints
# `made=50 gone=0` and `FAIL: 50 interface local(s) never released at scope
# exit`, and exits 1.
#
# The record and static-array rows run here too, asserting their VALUES rather
# than their frees — a released-too-early element reads back empty or garbage,
# which this does catch, while the leak itself stays a census measurement and
# lives in the ticket.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-scopeexit.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/scopeexit_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/scopeexit_slice.pas" "$work/s.wasm" \
    > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/s.wasm"

if grep -qE '^    (Local|main\$[0-9])' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Local|main\$[0-9])' "$work/cov.txt"
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
let code = 0;
try { inst.exports.main(); } catch (e) { if (e instanceof h.HostExit) code = e.code|0; else throw e; }
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(h.text(1));
process.exit(code);
JS

if node "$work/run.js" "$work/s.wasm" > "$work/wasm.txt"; then :; else
  echo "FAIL the slice exited nonzero under wasm — its own assertion tripped:"
  cat "$work/wasm.txt"
  exit 1
fi

[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
grep -qx "MANAGED LOCAL RELEASE OK" "$work/native.txt" || { echo "FAIL the NATIVE build did not reach its own sentinel, so this check is measuring a broken oracle"; exit 1; }

if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build: 50 interface locals made and 50"
  echo "..  destroyed at scope exit, plus 40 rounds of a record with managed"
  echo "..  fields and a static array of string read back intact; \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

echo "PASS check_scopeexit"
