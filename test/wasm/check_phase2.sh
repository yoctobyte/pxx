#!/bin/sh
# Phase 2 acceptance: pxx compiles Pascal to wasm, and the wasm answers what the
# native build answers.
#
# One source in two roles — native it prints, with -dWASM_NOMAIN its main is
# empty so the backend need not handle writeln (Phase 6). The harness calls the
# exported functions and diffs.
#
# Phase 2 is INCOMPLETE by construction: bodies the backend cannot lower are
# emitted as `unreachable` and reported. This script checks the bodies that ARE
# lowered, and prints the coverage line so incompleteness stays visible.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-phase2.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/phase2_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/phase2_slice.pas" "$work/p2.wasm" 2>&1 | head -1
wasm-validate "$work/p2.wasm"

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const inst = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), {});
const sp0 = inst.exports.sp.value;
const out = [
  inst.exports.AddMul(3, 4),
  inst.exports.AddMul(-2, 5),
  inst.exports.Chain(6),
  inst.exports.Chain(0),
];
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(out.join('\n') + '\n');
JS

node "$work/run.js" "$work/p2.wasm" > "$work/wasm.txt"
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") values), \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi
