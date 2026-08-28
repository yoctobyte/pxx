#!/bin/sh
# Phase 4 acceptance: direct calls. pxx compiles Pascal control flow to a wasm
# br_table dispatch loop, and the wasm answers what the native build answers.
#
# wasm has no calling convention to implement — arguments go on the operand
# stack in order and `call` consumes them — so what is left to get wrong is the
# FUNCTION INDEX. A call to the wrong function whose signature happens to match
# validates perfectly. Only the diff against the native build sees it.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-phase4.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/phase4_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`. Capture, then trim.
"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/phase4_slice.pas" "$work/p4.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/p4.wasm"

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const inst = new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), {});
const sp0 = inst.exports.sp.value;
// Mirrors the native main's writeln order. The duplication is deliberate: two
// independent expressions of the same call sequence is what makes this a
// differential test.
const e = inst.exports;
const out = [
  e.Chain(5),
  e.Fact(10),
  e.Fib(15),
  e.IsEven(10), e.IsEven(7), e.IsOdd(7),
  e.Apply(2),
  e.Widen(7, 10000000000n),
  e.UseBump(1),
  // Called twice on purpose: Discard's answer depends on a global the previous
  // call mutated, so a dropped side effect shows up as the SECOND value.
  e.Discard(3), e.Discard(3),
  e.UseMany(1),
];
// The shadow stack must come back to where it started. Recursion is what
// makes this sharp: Fib(15) enters ~1200 frames, so a prologue and epilogue
// that disagree by one byte is 1200 bytes of drift by the time it returns.
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(out.join('\n') + '\n');
JS

node "$work/run.js" "$work/p4.wasm" > "$work/wasm.txt"
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") values), \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/phase4_slice.pas" "$work" p4

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure. check_all.sh
# asserts this line is PRESENT rather than asserting nothing went wrong —
# "green is the absence of output" is indistinguishable from a script that died
# at line 1, which is how this suite stayed red across a handoff.
echo "PASS check_phase4"
