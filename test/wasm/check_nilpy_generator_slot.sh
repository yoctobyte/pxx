#!/bin/sh
# A managed local a NilPy generator holds ACROSS A YIELD must survive the yield
# on wasm32.
#
# Unlike most defects in this directory, this one IS a wrong value, so the
# native-vs-wasm differential that check_scopeexit.sh calls blind here is the
# primary assertion and it is sufficient. wasm32 printed `4 2` against x86-64's
# `4 5` at 0426b285ba35: `t` released at the yield, generator resumes holding a
# one-character string, no crash and no diagnostic.
#
# Verified to fail: with the skip predicate removed from WasmEmitManagedLocals
# and the compiler rebuilt, this prints the diff and exits 1.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-genslot.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/generator_slot_slice.npy" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/generator_slot_slice.npy" "$work/s.wasm" > /dev/null
wasm-validate "$work/s.wasm"

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
let code = 0;
try { inst.exports.main(); } catch (e) { if (e instanceof h.HostExit) code = e.code|0; else throw e; }
process.stdout.write(h.text(1));
process.exit(code);
JS

if node "$work/run.js" "$work/s.wasm" > "$work/wasm.txt"; then :; else
  echo "FAIL the slice exited nonzero under wasm:"; cat "$work/wasm.txt"; exit 1
fi

# The oracle has to have RUN. Comparing two empty files passes, and a NilPy
# frontend that refused the fixture outright would produce exactly that.
[ -s "$work/native.txt" ] || { echo "FAIL the native build produced NO output, so the diff below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
grep -qx "5" "$work/native.txt" || { echo "FAIL the native build did not print 5, so the oracle itself is wrong"; echo "     and this check would be measuring a broken reference:"; cat "$work/native.txt"; exit 1; }
echo "ok  the native oracle ran and printed the right answer"

# 5 is the discriminating value and 2 is what the defect produces; neither is a
# default, a zero, or a pointer width, so this row cannot pass on a blank.
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches native: a managed local built before a yield is still"
  echo "..  intact when the generator resumes (4 then 5, not 4 then 2)"
else
  echo "FAIL wasm diverges from native — the generator's persistent slot was"
  echo "     released at the yield"; exit 1
fi

echo "PASS check_nilpy_generator_slot"
