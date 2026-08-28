#!/bin/sh
# Phase 3 acceptance: control flow. pxx compiles Pascal control flow to a wasm
# br_table dispatch loop, and the wasm answers what the native build answers.
#
# The differential is the whole point here and not a formality. A dispatch bug
# — a block index off by one, a branch depth counted from the wrong nesting, a
# $pc read where it is stale — produces a module that VALIDATES and runs the
# wrong code. wasm-validate has nothing to say about any of them; only the diff
# against the native build does.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-phase3.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/phase3_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`. Capture, then trim.
"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/phase3_slice.pas" "$work/p3.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/p3.wasm"

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
  e.Max3(3, 1, 2), e.Max3(1, 3, 2), e.Max3(1, 2, 3),
  e.SumTo(10), e.SumTo(0),
  e.FactW(20n), e.FactW(1n),
  e.ForSum(5), e.ForSum(0),
  e.ForDown(5),
  e.RepUntil(4), e.RepUntil(0),
  e.CaseOf(0), e.CaseOf(2), e.CaseOf(4), e.CaseOf(9),
  e.BreakCont(10),
  e.ShortC(1, 1), e.ShortC(1, -1), e.ShortC(-1, -1),
  e.EarlyExit(-5), e.EarlyExit(21),
  e.NestLoop(3), e.NestLoop(100),
];
// The shadow stack must come back to where it started. A loop that leaks a
// frame per iteration still returns the right answer for a while.
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(out.join('\n') + '\n');
JS

node "$work/run.js" "$work/p3.wasm" > "$work/wasm.txt"
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
echo "PASS check_phase3"
