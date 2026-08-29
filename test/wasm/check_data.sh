#!/bin/sh
# Data-segment acceptance: the initialised blob. pxx lays Data[] into one active
# wasm data segment and a typed const reads back what the native build reads.
#
# What is being tested is an ADDRESS, not an opcode. A global whose storage is
# in the blob carries DATA_SYM_BIAS on its symbol offset, so its address is the
# $data global plus a displacement rather than a constant — a different
# addressing path from every other global, taken only by typed consts. Getting
# the base wrong by a whole region traps (past the end of memory, loud);
# getting it wrong by a few bytes reads a neighbouring const and answers a
# plausible number. Only the diff sees the second one.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-data.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

# Every module imports proc_exit (the RTL error reporters all end in Halt),
# so a bare `{}` import object no longer instantiates. wasmhost.js is the one
# place that knows what a pxx module needs.
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/data_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`. Capture, then trim.
"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/data_slice.pas" "$work/d.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/d.wasm"

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
const sp0 = inst.exports.sp.value;
// Run the program's initialisation before reading anything. A typed const
// RECORD is still built by startup code rather than stored in the blob (the
// sibling of bug-a-a-typed-const-array-is-built-by-startup-code-not-stored-as-data,
// which fixed the array case only), so Duo's fields are zero until this runs.
// Calling it is not a workaround: it is what running the program does, and
// this is the first slice whose correctness depends on top-level code at all.
inst.exports.main();
// Mirrors the native main's writeln order. The duplication is deliberate: two
// independent expressions of the same call sequence is what makes this a
// differential test.
const e = inst.exports;
const out = [
  e.Lookup(0), e.Lookup(5), e.Lookup(7),
  e.Wide(0), e.Wide(1), e.Wide(3),
  e.RealCmp(0, 1), e.RealCmp(1, 3), e.RealCmp(2, 0), e.RealCmp(3, 100),
  e.Table2(0, 0), e.Table2(1, 2), e.Table2(2, 3),
  e.PairA(), e.PairB(),
  // A BSS write and a blob read in one expression: the two addressing paths
  // interleaved, where a base confusion is a wrong number rather than a trap.
  e.Mixed(3),
  e.Sum(),
  e.SumWide(),
];
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(out.join('\n') + '\n');
JS

node "$work/run.js" "$work/d.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") values), \$sp balanced"
  echo "..  this is a pxx-vs-pxx diff, and it is the only assertion here about program"
  echo "..  BEHAVIOUR (the wat-oracle line below compares the encoder against itself). It claims"
  echo "..  BACKEND PARITY, not correctness. Both arms share the Pascal frontend,"
  echo "..  the AST and the IR, so a defect above that line is wrong identically on"
  echo "..  both sides and this check stays green. See face thirteen in"
  echo "..  devdocs/dev/differential-probes.md. For a claim above the IR the oracle"
  echo "..  has to be foreign (FPC), or the assertion absolute — neither is used here."
else
  echo "FAIL wasm diverges from native"; exit 1
fi

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/data_slice.pas" "$work" d

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure. check_all.sh
# asserts this line is PRESENT rather than asserting nothing went wrong —
# "green is the absence of output" is indistinguishable from a script that died
# at line 1, which is how this suite stayed red across a handoff.
echo "PASS check_data"
