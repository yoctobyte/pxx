#!/bin/sh
# A Variant written THROUGH A POINTER, on wasm32.
#
# ONE OPCODE, TWO QUESTIONS. The destination of a variant store arrives as an
# IR node and the wasm arm dispatched on `IRKind = IR_LOAD_SYM` alone. That
# opcode covers both "a load of a VARIANT symbol", whose address is its slot,
# and "a load of a POINTER symbol", whose address is the slot's VALUE. It chose
# the first reading for both, so `p^ := 42` through a `^Variant` wrote over the
# pointer VARIABLE instead of through it.
#
# TWO ARMS, AND ONLY ONE OF THEM IS LOUD — which is why the diff against the
# native build is the primary assertion and not a value grep:
#
#   * destination PRISTINE (a fresh pycell_new cell, tag 0): nothing traps and
#     the read answers None / 0. A plausible wrong value.
#   * destination LIVE: the payload lands where the tag belongs, and the next
#     read raises "variant holds an unknown tag". A different failure entirely.
#
# NO ROW EXPECTS 0 OR None. Those are what the defect produced, so such a row
# would pass with the store doing nothing at all.
#
# THE MUST-NOT-BREAK TWINS are not padding. var/out variant parameters were
# measured CORRECT before the fix and do not reach the pointer arm; a repair
# that over-reached into them, or into the generic pointer-store path that
# carries a 16-byte record, would break rows this slice runs on purpose.
#
# Found by: bug-a-a-nilpy-generator-fails-on-wasm32-while-three-other-targets-
# agree. A cell-promoted generator parameter gets a 16-byte pycell_new cell and
# the caller seeds it with `cell^ := arg` — the exact shape above. The cell
# stayed pristine, so every such parameter read None on wasm32 while native,
# i386 and arm32 agreed on the value.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-variantptr.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/variantptr_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through under `set -e`.
"$root/compiler/pascal26" --target=wasm32 \
    "$here/variantptr_slice.pas" "$work/v.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/v.wasm"

# The positive twin: a refused body becomes `unreachable` and still validates,
# so a slice where everything refused would pass the diff vacuously if the
# module trapped identically... it would not, but the census is free and it
# names WHICH routine went missing.
if grep -qE '^    (StoreInt|StoreStr|StoreFloat|CopyVar|ViaVarParam|ViaOutParam) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (StoreInt|StoreStr|StoreFloat|CopyVar|ViaVarParam|ViaOutParam) ' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

# wasihost.js, NOT the wasmhost.js shim: formatting a Double and a managed
# string pulls in the full WASI surface (fd_prestat_get, path_open, ...) and
# the shim provides two calls. The shim would fail at INSTANTIATION with a
# LinkError, which is loud, but it fails before running a single row.
node --no-warnings "$here/wasihost.js" "$work/v.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines)"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# Named individually, so a failure says which shape fell over rather than only
# that the file differed. The live-destination row is the one a value-only
# check cannot see: before the fix it RAISED rather than answering wrongly.
for want in int-thru=42 int-over-live=42 str-thru=through float-thru=2.50 \
            copy-thru=4242 read-thru=77; do
  if ! grep -qx "$want" "$work/wasm.txt"; then
    echo "FAIL a Variant store through a pointer is wrong: expected [$want]."
    echo "     The destination address came from the pointer's SLOT rather"
    echo "     than from its VALUE."
    exit 1
  fi
done
echo "ok  the store reached the pointee — pristine and live destinations, an"
echo "..  int, a managed string and a double payload, a variant-to-variant"
echo "..  copy with BOTH operands behind pointers, and a read back through one"

for want in var-param=44 out-param=45 plain-sym=46 'rec16-thru=11 22'; do
  if ! grep -qx "$want" "$work/wasm.txt"; then
    echo "FAIL a shape that was already correct has regressed: expected [$want]."
    echo "     var/out variant parameters and a 16-byte record through a"
    echo "     pointer do not go through the variant pointer arm."
    exit 1
  fi
done
echo "ok  the must-not-break twins are intact — var/out variant parameters, a"
echo "..  plain symbol store, and a 16-byte record through a pointer"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/variantptr_slice.pas" "$work" v

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_variantptr"
