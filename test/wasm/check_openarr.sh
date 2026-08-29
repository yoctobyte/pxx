#!/bin/sh
# Open-array parameters on wasm32, taken together with `Length of Pointer`.
#
# THE TWO CLASSES CANNOT BE TESTED APART, which is why they are one check:
# every open-array probe refused on Length/High in the CALLEE before it ever
# reached the parameter, so measuring one through the other's failure would
# credit a fix to the wrong change.
#
# THE ORACLE IS THE NATIVE BUILD, and here that is enough on its own — unlike
# check_dyn and check_defmem, which each needed a second instrument. Every way
# this can be wrong is a wrong ANSWER or a trap: a deref too few reads a handle
# as an element, a deref too many reads an element as a handle, and both show
# up in Length or in an indexed value. Saying so out loud rather than assuming
# it, because the previous two slices each needed the extra control and this
# one's exemption is a property of the feature, not a default.
#
# The refusal this replaced was STALE IN ITS REASON AND RIGHT IN ITS VERDICT:
# it named a layout that had shipped two phases earlier, and the one-liner its
# reason invites reports full coverage and then traps.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-openarr.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/openarr_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/openarr_slice.pas" "$work/oa.wasm" \
    > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/oa.wasm"

if grep -qE '^    (main\$[0-9]|SumOpen|FirstOpen|BumpOpen|SumNamed|BumpNamed|JoinOpen)' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (main\$[0-9]|SumOpen|FirstOpen|BumpOpen|SumNamed|BumpNamed|JoinOpen)' "$work/cov.txt"
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

node "$work/run.js" "$work/oa.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  the four argument paths — constructor, dynamic array, static array"
  echo "..  and empty — in const, by-value and \`var\` mode, with the write-back"
  echo "..  visible to the caller, plus managed string elements; \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# --- every deref depth, asserted by name ------------------------------------
# The four rows differ ONLY in how many times the callee derefs its slot, and
# a fix that gets one right can get the others wrong in either direction. A
# diff over the whole output would pass if the wrong rows happened to agree,
# so the depths are named individually.
miss=""
grep -q '^open  n=3 high=2 sum=60$'   "$work/wasm.txt" || miss="$miss open-array-from-dyn"
grep -q '^open  n=3 high=2 sum=18$'   "$work/wasm.txt" || miss="$miss open-array-from-static"
grep -q '^open  n=0 high=-1 sum=0$'   "$work/wasm.txt" || miss="$miss open-array-empty"
grep -q '^byval n=3 a0=10$'           "$work/wasm.txt" || miss="$miss open-array-byvalue"
grep -q '^caller sees a0=110 a2=130$' "$work/wasm.txt" || miss="$miss var-open-array-writeback"
grep -q '^named n=3 sum=360$'         "$work/wasm.txt" || miss="$miss named-dyn-const"
grep -q '^caller sees a0=1110$'       "$work/wasm.txt" || miss="$miss named-dyn-var-writeback"
grep -q '^strs  n=3 r=x.yy.zzz.$'     "$work/wasm.txt" || miss="$miss managed-elements"
if [ -n "$miss" ]; then
  echo "FAIL wrong deref depth on:$miss"
  cat "$work/wasm.txt"
  exit 1
fi
echo "ok  every deref depth is right, named one by one:"
echo "..  open array from a constructor, a dynamic array, a static array and"
echo "..  an empty one; by-value and \`var\` open arrays with the write-back"
echo "..  visible to the caller; a NAMED dyn-array parameter in both modes"
echo "..  (the other depth); and managed string elements through an open array"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/openarr_slice.pas" "$work" oa

# --- what this check does NOT catch, named rather than left implied ---------
# One shape is deliberately absent from the slice: an open-array-of-STRING
# argument written as a `[...]` CONSTRUCTOR. It refuses today, and the cause is
# not in this backend — ir.inc spills the argument through a hidden temp it
# declares tyAnsiString, because an open-array parameter records its ELEMENT
# kind in TypeKind and the spill guard reads that field without also testing
# IsArray. The temp then holds an array data pointer while claiming to be a
# managed string. The register backends absorb it (the mistyped retain and the
# scope-exit release cancel), so wasm32 is the only target that can see it.
# Filed as bug-a-open-array-of-string-arg-spilled-through-a-managed-string-temp.
# The dyn-array-fed `strs` row above covers open-arrays-of-managed-elements
# itself; it is only the constructor spelling that is missing, so this check
# would NOT notice a regression in that one path.

echo "PASS check_openarr"
