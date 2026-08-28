#!/bin/sh
# Indirect-call acceptance: procedural variables through the function table.
#
# A procvar is a table index here, and the failure that matters is calling the
# WRONG index with a matching signature — which validates perfectly and returns
# a plausible number. Only the diff against the native build sees it. (A wrong
# index with a mismatched signature traps: call_indirect checks the type at run
# time, which is the one guarantee this target gets for free.)
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-calls.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/calls_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`. Capture, then trim.
"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/calls_slice.pas" "$work/c.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/c.wasm"

# None of THIS slice's own routines may be among the unlowered. The coverage
# report legitimately lists RTL bodies waiting on the heap; a line naming a
# routine from this file means the phase did not do its job, and grepping for
# them is how that stays visible instead of hiding inside a body count.
if grep -qE '^    (Double_|Triple|Apply|CallDouble|CallTriple|Pick|SumApplied|IsAssigned) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Double_|Triple|Apply|CallDouble|CallTriple|Pick|SumApplied|IsAssigned) ' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

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
  e.CallDouble(21),
  e.CallTriple(21),
  e.Pick(0, 10), e.Pick(1, 10),
  e.SumApplied(10),
  e.IsAssigned(0), e.IsAssigned(1),
];
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(out.join('\n') + '\n');
JS

node "$work/run.js" "$work/c.wasm" > "$work/wasm.txt"
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") values), \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/calls_slice.pas" "$work" c

# ---- virtual dispatch: compiled and validated, NOT yet run ----------------
# Every routine in virtual_slice.pas begins with a class instantiation, which is
# a heap allocation, and the heap is a later phase. So this half asserts what
# can honestly be asserted today — the VMT path emits, no body here is
# unreachable for a DISPATCH reason, and the module validates — and says
# plainly that it does not assert dispatch. A check that went green here while
# proving less than it looks like is the failure mode this whole suite exists
# to avoid.
"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/virtual_slice.pas" "$work/v.wasm" > "$work/vcov.txt" 2>&1
wasm-validate "$work/v.wasm"
if grep -E '^    (TAnimal|TBird|TPenguin)\.' "$work/vcov.txt" > "$work/vbad.txt"; then
  echo "FAIL a virtual method was emitted as unreachable:"; cat "$work/vbad.txt"; exit 1
fi
echo "ok  virtual_slice compiles and validates; every method body lowered"
echo "..  NOT RUN: class instantiation needs the heap (a later phase). This"
echo "..  proves the VMT path emits and type-checks, not that it dispatches."

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure. check_all.sh
# asserts this line is PRESENT rather than asserting nothing went wrong —
# "green is the absence of output" is indistinguishable from a script that died
# at line 1, which is how this suite stayed red across a handoff.
echo "PASS check_calls"
