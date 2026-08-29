#!/bin/sh
# Zero-initialisation of managed LOCALS on wasm32, on a DIRTY frame.
#
# THE DIFF IS NEARLY VACUOUS WITHOUT THE DIRT, and that is the whole design of
# this check. Every bug it guards against is invisible on a clean stack: a slot
# that happens to hold zero behaves exactly like a slot that was zeroed. So the
# slice recurses through `Dirtier` before each row, writing recognisable
# non-zero words into shadow-stack memory the routine under test then reuses.
#
# Falsified against a build broken on purpose, 2026-08-29: with the zero-init
# pass removed from WasmEmitManagedLocals, `ViaRecord` dies with `memory access
# out of bounds` — it releases the dirty bytes of its unzeroed local record as
# if they were a live string handle. The plain-string row still PASSED in that
# build, which is the measurement that justifies the wide-extent rows existing
# separately rather than trusting one managed local to stand for all of them.
#
# Three assertions, because the diff alone cannot see any of the three:
#   * the VALUES, against the native build;
#   * the DIRT IS REAL — Dirtier's magic words must still be in the emitted
#     module. A dirtying routine the optimiser folded away leaves this whole
#     check testing a clean stack and passing for the wrong reason;
#   * the MECHANISM IS PRESENT — the wide-extent bodies must contain the
#     PXXMemZero call and the narrow ones must not. That distinguishes "zeroed
#     by this pass" from "happened to be zero", which no run-time observation
#     on a passing build can do.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-zeroinit.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/zeroinit_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/zeroinit_slice.pas" \
    "$work/s.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/s.wasm"

if grep -qE '^    (Via|Dirtier|main\$0)' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Via|Dirtier|main\$0)' "$work/cov.txt"
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
try { inst.exports.main(); } catch (e) { if (!(e instanceof h.HostExit)) throw e; }
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(h.text(1));
JS

node "$work/run.js" "$work/s.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines)"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

for row in \
  'record  payload 5' \
  'deep    inner/tag' \
  'strarr  8' \
  'rowarr  6' \
  'string  scalar' \
  'dyn     4'
do
  grep -qxF "$row" "$work/wasm.txt" || { echo "FAIL missing row: $row"; exit 1; }
done
echo "ok  every row asserted individually: a local record with a managed"
echo "..  field, a managed field two records deep, a static array of string,"
echo "..  a static array of dyn-array handles, and the two narrow cases"
echo "..  (scalar string, dynamic array) that already worked"

"$root/compiler/pascal26" --target=wasm32 "$here/zeroinit_slice.pas" \
    "$work/s.wat" > /dev/null 2>&1

# --- the dirt is real -------------------------------------------------------
# $11111111 = 286331153, $22222222 = 572662306. If Dirtier stops writing them
# the slice runs on a clean stack and every row above passes for free.
for magic in 286331153 572662306; do
  if ! awk '/\(func \$Dirtier\$/,/^  \)$/' "$work/s.wat" \
       | grep -q "i32.const $magic"; then
    echo "FAIL Dirtier no longer writes $magic, so the frames the routines"
    echo "     below reuse are not dirty and this whole check is testing a"
    echo "     clean stack — where every zero-init bug is invisible."
    exit 1
  fi
done
echo "ok  Dirtier still writes its magic words, so the frames under test are"
echo "..  genuinely hostile and not merely assumed to be"

# --- the mechanism is present, and only where it belongs --------------------
# A wide extent (> pointer) routes to PXXMemZero; a pointer-sized one is an
# inline i32.store. Asserting BOTH directions is what makes this mean
# "this pass zeroed it" rather than "something zeroed it": a pass that called
# PXXMemZero for every managed local would satisfy the first half alone and
# cost a call per string local.
for f in ViaRecord ViaDeep ViaStrArray ViaRowArray; do
  # `|| true` on the count, and ONLY on the count: grep -c exits 1 when the
  # answer is zero, which is a legitimate ANSWER here and not a failure, and
  # `set -e` would otherwise kill the script with no message at all — which is
  # exactly what it did the first time this loop ran.
  n=$(awk "/\(func \\\$$f\\\$/,/^  \)\$/" "$work/s.wat" | grep -c 'call \$PXXMemZero' || true)
  if [ "$n" -lt 1 ]; then
    echo "FAIL $f has a managed local whose extent exceeds a pointer, and its"
    echo "     body contains no PXXMemZero call — so nothing zeroed it and the"
    echo "     row above passed because the frame happened to be clean there."
    exit 1
  fi
done
for f in ViaString ViaDyn Dirtier; do
  # `|| true` on the count, and ONLY on the count: grep -c exits 1 when the
  # answer is zero, which is a legitimate ANSWER here and not a failure, and
  # `set -e` would otherwise kill the script with no message at all — which is
  # exactly what it did the first time this loop ran.
  n=$(awk "/\(func \\\$$f\\\$/,/^  \)\$/" "$work/s.wat" | grep -c 'call \$PXXMemZero' || true)
  if [ "$n" -ne 0 ]; then
    echo "FAIL $f has only pointer-sized (or no) managed locals and should be"
    echo "     zeroed with an inline i32.store, but its body calls PXXMemZero"
    echo "     $n time(s) — a call per managed local is the cost this split"
    echo "     exists to avoid."
    exit 1
  fi
done
echo "ok  wide extents go to PXXMemZero and pointer-sized ones do not — the"
echo "..  split is width, asserted in both directions so a pass that called"
echo "..  the helper for everything would fail here"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/zeroinit_slice.pas" \
   "$work" s

# --- what this check does NOT catch -----------------------------------------
#  * a VARIANT local, a COM INTERFACE local, a static array of either, and a
#    promotable-int local. ManagedLocalZeroBytes covers all four and this pass
#    now asks that table rather than a private list, so they are zeroed by
#    construction — but none is exercised here, because none of them lowers on
#    this target yet for other reasons.
#  * a NilPy tyClass local, same table, same reason.
#  * the RELEASE half. It keeps its own narrower predicate on purpose (what
#    must start nil is a different question from what this backend knows how to
#    release) and check_dyn / check_managed own it.
#  * whether the dirt actually reaches the specific slots under test. Dirtier
#    makes the region hostile; it does not prove any particular offset is
#    non-zero. The falsification against a deliberately broken build is what
#    establishes that it reaches far enough, and that is a measurement from
#    2026-08-29, not an invariant this script re-checks.
echo "PASS check_zeroinit"
