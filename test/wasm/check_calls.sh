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

# Every module imports proc_exit (the RTL error reporters all end in Halt),
# so a bare `{}` import object no longer instantiates. wasmhost.js is the one
# place that knows what a pxx module needs.
cp "$here/wasmhost.js" "$work/"

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
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
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
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") values), \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/calls_slice.pas" "$work" c

# ---- virtual dispatch, interfaces, construction ---------------------------
"$root/compiler/pascal26" "$here/virtual_slice.pas" "$work/vnative" >/dev/null
"$work/vnative" > "$work/vnative.txt"
"$root/compiler/pascal26" --target=wasm32 -dWASM_NOMAIN \
    "$here/virtual_slice.pas" "$work/v.wasm" > "$work/vcov.txt" 2>&1
wasm-validate "$work/v.wasm"
if grep -E '^    (TAnimal|TBird|TPenguin)\.' "$work/vcov.txt" > "$work/vbad.txt"; then
  echo "FAIL a virtual method was emitted as unreachable:"; cat "$work/vbad.txt"; exit 1
fi

cat > "$work/vrun.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
const e = inst.exports;
const out = [
  e.AnimalLegs(), e.BirdLegs(),
  e.BirdSpeakViaBase(), e.PenguinSpeak(),
  e.BirdDescribe(), e.PenguinDescribe(),
  e.TotalSpeak(),
];
process.stdout.write(out.join('\n') + '\n');
JS

node "$work/vrun.js" "$work/v.wasm" > "$work/vwasm.txt"
[ -s "$work/vnative.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/vnative.txt" "$work/vwasm.txt"; then
  echo "ok  virtual dispatch matches the native build (7 values)"
else
  echo "FAIL virtual dispatch diverges from native"; exit 1
fi

# ---- and the limitation that green does NOT cover -------------------------
# Everything above passes on a heap that starts at ADDRESS ZERO. HeapMmap has
# no wasm32 arm, so it returns 0, and PXXAlloc does not check it — deliberately,
# because on a hosted target a failed mmap returns a negative errno and the next
# access faults. Linear memory has nothing to fault on: address 0 is legal,
# loads return zero, there is no page protection. So allocation works and stays
# correct until roughly 1 KB, and then overwrites BSS.
#
# This is asserted rather than commented, and it is asserted as the CURRENT
# state: it asserted the DEFECT — that allocation still began below 1024 — and
# was written to fail the day the fix landed, so this paragraph could not
# outlive its cause. It fired on 2026-08-29 and this is the rewrite.
#
# The assertion is now the opposite one, and it is a PROPERTY rather than a new
# fact about the arena: every dispatch result above was read off an object that
# sits clear of the null guard. Nothing here names the arena's address or its
# size — check_managed.sh owns those — because what this check needs from the
# heap is only that it is a real one.
#   bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero, landed
cat > "$work/heap.pas" <<'PAS'
program HeapProbe;
type TA = class Code: Integer; end;
var a: TA;
function Addr1: Integer; begin a := TA.Create; a.Code := 11; Addr1 := Integer(a); end;
begin
end.
PAS
"$root/compiler/pascal26" --target=wasm32 "$work/heap.pas" "$work/heap.wasm" >/dev/null 2>&1
cat > "$work/heap.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
process.stdout.write(String(inst.exports.Addr1()) + '\n');
JS
addr=$(node "$work/heap.js" "$work/heap.wasm")
if [ "$addr" -lt 1024 ]; then
  echo "FAIL an object was constructed at $addr, inside the 1024-byte null"
  echo "     guard. Address 0 is a legal wasm address that reads as zero, so"
  echo "     this does not fault — the object works, and then the next kilobyte"
  echo "     of allocation silently overwrites BSS."
  echo "     bug-a-heapmmap-has-no-wasm32-arm... regressed."
  exit 1
fi
echo "ok  the object above was constructed at $addr, clear of the null guard —"
echo "..  so every dispatch result in this check was read off a real heap"

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure. check_all.sh
# asserts this line is PRESENT rather than asserting nothing went wrong —
# "green is the absence of output" is indistinguishable from a script that died
# at line 1, which is how this suite stayed red across a handoff.
echo "PASS check_calls"
