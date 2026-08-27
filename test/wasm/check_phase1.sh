#!/bin/sh
# Phase 1 acceptance: pxx's own wasm encoder, checked against the external oracle.
#
#   1. our .wasm validates
#   2. our .wat PARSES (wat2wasm accepts it)
#   3. both describe the SAME MODULE — wasm2wat of each, diffed
#   4. both RUN and produce the same trace under node
#
# (3) is the one that matters. The binary and the text come from one model in
# wasmenc.inc, so agreement is meant to be structural; this is what proves it
# rather than asserting it.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-phase1.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/wasmenc_selftest.pas" "$work/selftest" >/dev/null
"$work/selftest" "$work/ours" >/dev/null

wasm-validate "$work/ours.wasm"
echo "ok  our .wasm validates ($(wc -c < "$work/ours.wasm") bytes)"

wat2wasm "$work/ours.wat" -o "$work/fromtext.wasm"
wasm-validate "$work/fromtext.wasm"
echo "ok  our .wat parses and validates"

wasm2wat "$work/ours.wasm"    -o "$work/a.wat"
wasm2wat "$work/fromtext.wasm" -o "$work/b.wat"
if diff -u "$work/a.wat" "$work/b.wat" > "$work/d"; then
  echo "ok  .wasm and .wat describe the same module"
else
  echo "FAIL .wasm and .wat differ:"; cat "$work/d"; exit 1
fi

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const out = [];
const inst = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])),
  { env: { print: (n) => out.push(n) } });
const sp0 = inst.exports.sp.value;
inst.exports.main();
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(out.join('\n') + '\n');
JS

node "$work/run.js" "$work/ours.wasm"     > "$work/ra.txt"
node "$work/run.js" "$work/fromtext.wasm" > "$work/rb.txt"
cat > "$work/expected.txt" <<'EXP'
14
-1
-64
-65
63
64
123456789
-2147483648
2147483647
EXP
diff "$work/expected.txt" "$work/ra.txt" >/dev/null || { echo "FAIL binary trace"; diff -u "$work/expected.txt" "$work/ra.txt"; exit 1; }
diff "$work/ra.txt" "$work/rb.txt" >/dev/null || { echo "FAIL text-built trace differs"; exit 1; }
echo "ok  both run under node, trace matches expected, \$sp balanced"
