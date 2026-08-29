#!/bin/sh
# Aggregate function results on wasm32 — the caller-owned hidden destination.
#
# THE ORACLE IS THE NATIVE BUILD. abi.inc's RetViaHiddenDest is one convention,
# not five features: a record, a set, a variant, a promotable int and a frozen
# string all come back through a destination the CALLER allocates and the
# callee fills. Every register target has a spare register to carry that
# pointer (x8 on aarch64, r10 on x86-64). wasm has none and cannot invent one,
# so here it is a trailing PARAMETER, and the whole arm is that one difference.
#
# What makes this worth a diff rather than a compile check: the failure mode is
# a wrong VALUE, not a trap. The first working version of this arm compiled,
# validated, reported `125 of 125 bodies lowered`, ran to completion — and
# returned `x=3 y=8`, the y field holding the byte-count argument of the
# memmove that had just overwritten it. Nothing but comparing against native
# would have said so.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-aggret.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/aggret_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/aggret_slice.pas" "$work/ag.wasm" \
    > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/ag.wasm"

if grep -qE '^    (main\$[0-9]|Make[A-Za-z]+)' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (main\$[0-9]|Make[A-Za-z]+)' "$work/cov.txt"
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

node "$work/run.js" "$work/ag.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  a record, a fixed array whose kind is only its ELEMENT's, a frozen"
  echo "..  string, and a record with a frozen-string field; \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# --- each shape named, because a diff passes if the wrong rows agree ---------
miss=""
grep -q '^rec   x=3 y=4$'            "$work/wasm.txt" || miss="$miss record"
grep -q '^arr   10 11 12 13$'        "$work/wasm.txt" || miss="$miss fixed-array"
grep -q '^str   pos neg$'            "$work/wasm.txt" || miss="$miss frozen-string"
grep -q '^recs  tag=7 name=rec$'     "$work/wasm.txt" || miss="$miss record-with-string-field"
grep -q '^temp  42$'                 "$work/wasm.txt" || miss="$miss unnamed-destination"
grep -q '^two   32$'                 "$work/wasm.txt" || miss="$miss two-live-destinations"
grep -q '^loop  60$'                 "$work/wasm.txt" || miss="$miss destination-reused-in-loop"
if [ -n "$miss" ]; then
  echo "FAIL wrong aggregate result for:$miss"
  cat "$work/wasm.txt"
  exit 1
fi
echo "ok  every result shape is right, named one by one:"
echo "..  a record; a fixed array (invisible to the kind-only oracle); a"
echo "..  frozen string; a record with a frozen-string field; a destination"
echo "..  the lowering minted rather than named; two live at once; and one"
echo "..  reused on every trip through a loop"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/aggret_slice.pas" "$work" ag

# --- what this check does NOT catch, named rather than left implied ----------
# THREE OF THE FIVE SHAPES THE CONVENTION COVERS ARE NOT TESTED HERE, and not
# because they pass. A set result needs set CONSTRUCTION (`value IR op 33`) and
# `in` against a set VARIABLE (`binary operator 99`); a variant result and a
# promotable-int result have their own unimplemented shapes. All three travel
# by this same hidden destination, so the convention is landing UNTESTED for
# them, and a regression in the set or variant path would not be seen here.
# Said out loud because "records work" reads as "aggregate results work".
#
# Also absent: an INDIRECT or VIRTUAL call returning an aggregate. Those keep
# refusing by design — WasmNodeIsAggRetCall asks about a DIRECT call
# specifically — so this check would not notice if they started yielding
# whatever happened to be on the operand stack.
#
# And a record VALUE PARAMETER (`SumP(p: TP)`) is a different convention this
# target does not implement; it was deliberately removed from the slice so a
# failure here means the result convention broke, not the parameter one.

echo "PASS check_aggret"
