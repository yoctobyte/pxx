#!/bin/sh
# IR_DEFAULT_MEM (statement IR op 52) on wasm32 — zero a block of memory.
#
# THE ORACLE IS THE NATIVE BUILD, plus one thing the diff cannot supply on its
# own. A skipped zeroing reads whatever was in that memory already, and on a
# fresh shadow stack that is usually zero — so the wrong build and the right
# build print the same thing and the diff is green. The slice therefore fills
# the region with $5A5A5A5A before every call (`Dirty`), which turns "we did
# not zero" from an invisible accident into a visible 1515870810.
#
# That is the same reuse-forcing shape check_dyn.sh needed for the retain, and
# it is here for the same reason: an instrument that can only see a DIFFERENCE
# is blind to an error both sides make, and "the memory happened to be zero" is
# an error both sides make. See face thirteen in devdocs/dev/differential-probes.md.
#
# 75 of compiler.pas's 166 remaining refusal lines were this — the leader after
# `in` landed, and a FIRST-refusal count like every number in that histogram.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-defmem.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/defmem_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/defmem_slice.pas" "$work/dm.wasm" \
    > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/dm.wasm"

if grep -qE '^    (main\$[0-9]|Dirty|Take|Take2|Pair|One|Two|Both|Twice)' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (main\$[0-9]|Dirty|Take|Take2|Pair|One|Two|Both|Twice)' "$work/cov.txt"
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

node "$work/run.js" "$work/dm.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  a zeroed method-pointer temp for a nil argument, two temps in one"
  echo "..  call, and two calls back to back; \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# --- the zeroing is OBSERVED, not merely diffed -----------------------------
# The lines above would also pass if both builds skipped the zeroing and the
# memory happened to be clear — and an EARLIER version of this slice did
# exactly that. It called Take(nil) from the main body, whose frame Dirty can
# never reach, so the temps landed on already-zero memory and all three
# falsification breaks passed, including deleting the zeroing outright. The
# wrappers in the slice put the temps at Dirty's call depth. Only the Code half
# of each temp is ever written, so DATA is the witness: it is zero only because
# the zeroing made it so.
if grep -q '1515870810' "$work/wasm.txt" && \
   [ "$(grep -c 'code=0 data=0' "$work/wasm.txt")" -ge 3 ] && \
   grep -q '^pair 0 0 / 0 0$' "$work/wasm.txt"; then
  echo "ok  the temps really are zero, and the dirtying really happened —"
  echo "..  \$5A5A5A5A is present in the output, so a skipped zeroing would"
  echo "..  have shown 1515870810 in a code=/data= field rather than 0"
else
  echo "FAIL the zeroing assertion did not hold. Either a temp was not zeroed,"
  echo "     or Dirty stopped reaching the region the temp lands in — in which"
  echo "     case this check has quietly stopped testing anything. Got:"
  cat "$work/wasm.txt"
  exit 1
fi

# --- what this check does NOT catch, established by falsification ----------
# Three breaks were tried. Removing the zeroing outright is caught, with
# data=1515870810 on every temp. The other two are NOT caught, and both for
# reasons that are properties of the construct rather than gaps here:
#
#   halving the byte count  — the method-pointer record DECLARES 16 bytes on
#     every target (symtab.inc EnsureMethodPtrRec hard-codes it), while a
#     32-bit target's real payload is 8. Half of 16 still covers all 8, so the
#     break is invisible. Filed separately; it is a shared-file bug, not this
#     arm's.
#   zeroing at dest+4    — Code is overwritten by the argument store straight
#     after the zeroing, so the only field that witnesses anything is Data, and
#     that break zeroes Data correctly.
#
# Recorded because "three breaks, one caught" reads like a weak check, and the
# distinction between a break a check cannot see and a break that changes
# nothing observable is the whole difference.

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/defmem_slice.pas" "$work" dm

echo "PASS check_defmem"
