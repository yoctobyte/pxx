#!/bin/sh
# Managed locals must be released when an exception unwinds THROUGH a frame.
#
# THE EPILOGUE NEVER RUNS. `Middle` owns an interface, calls something that
# raises, and neither catches nor returns -- so its own epilogue is skipped and
# the eventual handler's frame releases only what IT owns. Without a proc
# cleanup frame, everything the unwound-through frame held is leaked. wasm32 had
# no such frame: TargetHasProcCleanupFrame covered six targets and not this one,
# and the frontend hook that gives the register backends theirs writes machine
# bytes into Code[] and returns a patch position, which this backend cannot use.
#
# SEPARATE FROM check_scopeexit ON PURPOSE. That covers the ordinary return
# path; this covers the path where the epilogue is skipped entirely. They are
# different mechanisms, and one probe going red for either would be one
# assertion wearing two names -- the lane's own rule, from check_dyn.
#
# Measured on the pre-fix backend (node host):
#
#     made=20 gone=0         every interface leaked on the unwind
#     $sp ended 16 low       the shadow stack did not come back either
#
# and after: gone=20, $sp exactly balanced, which is what the native oracle
# says. The $sp row is the runner's own assertion and is checked below; it is
# reported here because it moved with the fix, not because the fix targeted it.
#
# Verified to fail: against the backend one commit earlier this prints
# `LEAK: 20 not released on unwind` and exits 1.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-unwindrel.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/unwindrel_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/unwindrel_slice.pas" "$work/s.wasm" \
    > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/s.wasm"

if grep -qE '^    (Local|main\$[0-9])' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Local|main\$[0-9])' "$work/cov.txt"
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
let code = 0;
try { inst.exports.main(); } catch (e) { if (e instanceof h.HostExit) code = e.code|0; else throw e; }
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(h.text(1));
process.exit(code);
JS

if node "$work/run.js" "$work/s.wasm" > "$work/wasm.txt"; then :; else
  echo "FAIL the slice exited nonzero under wasm — its own assertion tripped:"
  cat "$work/wasm.txt"
  exit 1
fi

[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
grep -qx "UNWIND RELEASE OK" "$work/native.txt" || { echo "FAIL the NATIVE build did not reach its own sentinel, so this check is measuring a broken oracle"; exit 1; }

if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build: 20 interface locals made and 20"
  echo "..  destroyed while an exception unwound THROUGH the frame that owned"
  echo "..  them, the epilogue never running; \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

echo "PASS check_unwindrel"
