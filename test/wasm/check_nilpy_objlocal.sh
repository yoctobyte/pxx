#!/bin/sh
# A NilPy object bound to a LOCAL must be released at scope exit on wasm32.
#
# WasmEmitManagedLocals is the seventh copy of the scope-exit managed-local
# release loop, and until 2026-09-06 it was missing exactly one row of the six
# every other backend carries: the tyClass arm. PXXObjRelease appeared nowhere
# in ir_codegen_wasm32.inc. So every NilPy class instance held in a local
# leaked, once per call, on wasm32 and on no other target.
#
# WHY NO EXISTING CHECK COULD SEE IT, and why this file is separate from
# check_scopeexit.sh rather than another row in it:
#
#   1. The arm is gated on `NilPyUserCode and PyClassSymArcEligible(i)`, so a
#      Pascal slice cannot reach it at all. check_scopeexit.sh's fixture is
#      .pas and always will be.
#   2. A leak does not corrupt. This program printed 1999000 correctly with
#      1900 objects stranded, and prints the same 1999000 now. Every value
#      assertion in this directory passes on both sides of the defect --
#      including a native-vs-wasm diff, because BOTH sides print the same
#      right answer. Only the allocation census reads the quantity that moves.
#   3. x86-64 has the row. The dev loop, gate.sh quick and the pin all run
#      there, so the whole instrument that would normally catch this is
#      pointed at the one target where it was already correct.
#
# THE ASSERTION IS A SLOPE, NOT A COUNT. `live` is compared BETWEEN two runs at
# different iteration counts, never against a fixed number, for the reason
# frankA's target-axis note gives: a per-target constant rots, while a relation
# carries no expected width and prints a different correct number on each
# target. wasm32 settles at live=2 and x86-64 at live=1; both are flat, and
# flat is the claim.
#
# Verified to fail: against the backend at d58828d8c^ this prints
#   FAIL wasm32 live grew 1900 -> 7815 across the N step
# and exits 1. Against d58828d8c it prints 2 -> 2.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-objlocal.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

LO=2000
HI=8000

cat > "$work/run.js" <<'JS'
const fs = require('fs');
const host = require('./wasmhost.js');
const h = host();
const inst = h.bind(new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(process.argv[2])), h.imports));
let code = 0;
try { inst.exports.main(); } catch (e) { if (e instanceof h.HostExit) code = e.code|0; else throw e; }
// The census goes to fd 2 and the program's own output to fd 1. Both are
// wanted: the census is the measurement and fd 1 is the guard that a "fix"
// which simply stopped computing would not pass.
process.stdout.write(h.text(1));
process.stderr.write(h.text(2));
process.exit(code);
JS

# field <line> <name> -- pull one `name=<int>` out of a census line
field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=\([0-9]*\)$/\1/p"; }

for n in $LO $HI; do
  sed "s/N_ITERS/$n/" "$here/objlocal_slice.npy" > "$work/slice_$n.npy"

  "$root/compiler/pascal26" -dPXX_ALLOC_CENSUS "$work/slice_$n.npy" "$work/native_$n" > /dev/null
  "$work/native_$n" > "$work/native_$n.out" 2> "$work/native_$n.err"

  "$root/compiler/pascal26" -dPXX_ALLOC_CENSUS --target=wasm32 \
      "$work/slice_$n.npy" "$work/wasm_$n.wasm" > "$work/cov_$n.txt" 2>&1
  wasm-validate "$work/wasm_$n.wasm"
  if node "$work/run.js" "$work/wasm_$n.wasm" > "$work/wasm_$n.out" 2> "$work/wasm_$n.err"; then :; else
    echo "FAIL the slice exited nonzero under wasm at N=$n:"; cat "$work/wasm_$n.out" "$work/wasm_$n.err"; exit 1
  fi
done

# ---- preconditions, each branched on -------------------------------------
# A precondition that is not branched on is a comment. Every one of these can
# fail, and each fails for a DIFFERENT reason than the assertion below.

expected_lo=$(( LO * (LO - 1) / 2 ))
expected_hi=$(( HI * (HI - 1) / 2 ))
for pair in "native_$LO $expected_lo" "wasm_$LO $expected_lo" "native_$HI $expected_hi" "wasm_$HI $expected_hi"; do
  set -- $pair
  got=$(tr -d ' \r' < "$work/$1.out")
  [ "$got" = "$2" ] || { echo "FAIL $1 printed '$got', not $2 -- the program did not compute"; echo "     its own answer, so a flat census below would mean nothing ran"; exit 1; }
done
echo "ok  both targets compute the slice's own answer at both counts"

for tag in "native_$LO" "wasm_$LO" "native_$HI" "wasm_$HI"; do
  eval "line_${tag%%_*}_$(echo $tag | sed 's/.*_//')=" 2>/dev/null || true
done

get_last() { grep 'allocs=' "$work/$1.err" | tail -1; }

for tag in "native_$LO" "wasm_$LO" "native_$HI" "wasm_$HI"; do
  l=$(get_last "$tag")
  [ -n "$l" ] || { echo "FAIL no census line from $tag -- built without"; echo "     -dPXX_ALLOC_CENSUS, or nothing was allocated at all. Either way"; echo "     the slope below had no numbers and would have compared empty to empty"; exit 1; }
done
echo "ok  every run produced a census, so the slope has numbers to compare"

nl_lo=$(get_last "native_$LO"); nl_hi=$(get_last "native_$HI")
wl_lo=$(get_last "wasm_$LO");   wl_hi=$(get_last "wasm_$HI")

na_lo=$(field "$nl_lo" allocs); na_hi=$(field "$nl_hi" allocs)
wa_lo=$(field "$wl_lo" allocs); wa_hi=$(field "$wl_hi" allocs)

# The machinery must actually SCALE with N. Without this row a compiler that
# stopped allocating objects entirely would produce a flat `live` and pass the
# assertion below -- the failure value and the expected value would collide.
for pair in "native $na_lo $na_hi" "wasm32 $wa_lo $wa_hi"; do
  set -- $pair
  [ "$3" -gt $(( $2 * 2 )) ] || { echo "FAIL $1 allocs did not scale with N ($2 -> $3 for a 4x step)."; echo "     The object is not being allocated, so 'it does not leak' is vacuous"; exit 1; }
done
echo "ok  allocations scale with N on both targets -- the objects are real"

# ---- the assertion -------------------------------------------------------
nv_lo=$(field "$nl_lo" live); nv_hi=$(field "$nl_hi" live)
wv_lo=$(field "$wl_lo" live); wv_hi=$(field "$wl_hi" live)

# A RELATION, not a constant: live must not grow with N. The margin absorbs
# fixed bookkeeping that differs per target (native settles at 1, wasm32 at 2)
# without admitting a per-iteration slope, which at this N step is in the
# thousands.
fail=0
[ $(( nv_hi - nv_lo )) -le 8 ] || { echo "FAIL native live grew $nv_lo -> $nv_hi across the N step"; fail=1; }
[ $(( wv_hi - wv_lo )) -le 8 ] || { echo "FAIL wasm32 live grew $wv_lo -> $wv_hi across the N step"; fail=1; }
[ "$fail" = 0 ] || { echo "     A NilPy object bound to a local is not being released at scope exit."; exit 1; }

echo "ok  live is flat across a 4x N step on BOTH targets:"
echo "..  native $nv_lo -> $nv_hi, wasm32 $wv_lo -> $wv_hi"
echo "..  (the numbers differ per target and are not asserted; the slope is)"
echo "PASS check_nilpy_objlocal"
