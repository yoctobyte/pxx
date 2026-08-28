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

# NOT piped into head: a pipeline's exit status is the LAST command's, so
# `pascal26ns ... | head -1` under `set -e` reports head's success and a failed
# compile sails through. Capture, check, then trim.
"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/phase2_slice.pas" "$work/p2.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/p2.wasm"

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const inst = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), {});
const sp0 = inst.exports.sp.value;
// Mirrors the native main's writeln order. The duplication is deliberate: two
// independent expressions of the same call sequence is what makes this a
// differential test — generating one from the other would cancel a bug in the
// generator against itself.
// i64 crosses the JS boundary as BigInt, which prints without the `n`, so the
// two sides' text compares directly.
let out = [
  inst.exports.AddMul(3, 4),
  inst.exports.AddMul(-2, 5),
  inst.exports.Chain(6),
  inst.exports.Chain(0),
  inst.exports.Wide(3000000000n, 4n),
  inst.exports.Wide(-5n, 7n),
  inst.exports.Mix(-7, 10000000000n),
  inst.exports.Narrow(2147483647n),
  inst.exports.Narrow(-1n),
  inst.exports.Pack(0),
  inst.exports.Pack(1000),
  // Booleans cross as 0/1; Number() matches what native's Ord() prints.
  Number(inst.exports.LtI(1, 2)),
  Number(inst.exports.LtI(2, 2)),
  Number(inst.exports.EqI(2, 2)),
  Number(inst.exports.GeI(3, 2)),
  Number(inst.exports.GeI(1, 2)),
  Number(inst.exports.LtU(-1, 1)),          // 4294967295 as an i32 bit pattern
  Number(inst.exports.LtU(1, -1)),
  Number(inst.exports.LtW(-10000000000n, 1n)),
  Number(inst.exports.EqW(10000000000n, 10000000000n)),
  inst.exports.Negate(-2147483647),
  inst.exports.NegateW(-10000000000n),
  inst.exports.BitNot(0),
  inst.exports.BitNot(-13),
  Number(inst.exports.LogNot(0)),
  Number(inst.exports.LogNot(1)),
  inst.exports.Bits(120, 5),
  inst.exports.BitsW(8000000000n, 5n),
  inst.exports.BumpG(5),
  inst.exports.BumpG(7),
  inst.exports.BumpW(10000000000n),
  inst.exports.BumpW(-3n),
];
// The scratch global's address: the native side passes a real pointer here and
// the wasm side needs the i32, so the address itself is never compared — only
// what the two builds do through it.
const scratch = inst.exports.ScratchAddr();
out.push(inst.exports.Poke(scratch, 1234));
out.push(inst.exports.Poke(scratch, -7));
inst.exports.AddTo(scratch, 100);
out.push(inst.exports.GetScratch());
out.push(inst.exports.ArrSum(3));
out.push(inst.exports.ArrSum(0));
out.push(inst.exports.GlobArr(5));
out.push(inst.exports.RecField(7));
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

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure. check_all.sh
# asserts this line is PRESENT rather than asserting nothing went wrong —
# "green is the absence of output" is indistinguishable from a script that died
# at line 1, which is how this suite stayed red across a handoff.
echo "PASS check_phase2"
