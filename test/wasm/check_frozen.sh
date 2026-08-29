#!/bin/sh
# Frozen strings: string[N], ShortString, the record field, the parameter.
#
# A frozen string is a BUFFER — an 8-byte length prefix then the characters,
# inline in the frame, in BSS, or inside a record — so `s := x` is a
# length-clamped COPY and not a store, and every source shape reaches it by a
# different route. That is the whole risk: a copy that ignores the capacity
# writes past the variable into whatever the frame put next to it and prints
# the right answer until something else moves.
#
# So the oracle is the NATIVE build, which is a genuinely separate backend
# reached through the same frontend, and the assertions below are arranged so
# that reverting the lowering cannot leave them true:
#
#   * remove the frozen store and the body is `unreachable` — the module traps,
#     and both the diff and the mechanism assertion fail;
#   * remove the capacity CLAMP and three lines of the diff change, because the
#     slice truncates on purpose in three different shapes;
#   * overrun the record field and `r.tail`, the neighbour printed right after
#     it, changes.
#
# The one thing a native-vs-wasm diff cannot see is a rule both backends get
# wrong together, which is why the expected truncations are asserted by VALUE
# below rather than only compared: a later edit that made every string fit
# would silently delete the coverage while leaving the diff green.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-frozen.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/frozen_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

# The truncating cases must still be truncating. Asserted on the NATIVE output,
# which is the oracle: if these stop holding, the slice has drifted and the
# diff below is no longer testing the clamp at all.
for expect in 'trunc|5' 'abcdefghijklmno|15' 'field na|8|3|77'; do
  if ! grep -qxF "$expect" "$work/native.txt"; then
    echo "FAIL the slice no longer exercises truncation: expected a line '$expect'"
    cat "$work/native.txt"
    exit 1
  fi
done
echo "ok  the slice still truncates in all three shapes (string[N], the"
echo "..  16-into-15 case, and the record field with a live neighbour)"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`. Capture, then trim.
"$root/compiler/pascal26" --target=wasm32 \
    "$here/frozen_slice.pas" "$work/f.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/f.wasm"

if grep -qE '^    (ShowConst|Mut|main\$0) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (ShowConst|Mut|main\$0) ' "$work/cov.txt"
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
try { inst.exports.main(); }
catch (e) { if (!(e instanceof h.HostExit)) throw e; }
if (inst.exports.sp.value !== sp0) {
  console.error(`FAIL shadow stack leaked: ${sp0} -> ${inst.exports.sp.value}`);
  process.exit(1);
}
process.stdout.write(h.text());
JS

node "$work/run.js" "$work/f.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  literal, Char, frozen-to-frozen and empty sources; truncation in"
  echo "..  three shapes; Length; indexing; a record field and its neighbour;"
  echo "..  const and by-value frozen parameters, \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# The MECHANISM, not just the answer. A frozen store is a clamp and a
# PXXMemMove; something that produced the right characters by a different
# route — a fixed-size copy, say — would pass the diff on this slice and
# overrun on a wider one.
"$root/compiler/pascal26" --target=wasm32 \
    "$here/frozen_slice.pas" "$work/f.wat" > /dev/null 2>&1
if grep -q 'i32.gt_s' "$work/f.wat" && grep -q 'select' "$work/f.wat" \
   && grep -q 'call \$PXXMemMove' "$work/f.wat"; then
  echo "ok  the store is a clamp and a PXXMemMove, not a fixed-size copy"
else
  echo "FAIL the frozen store does not go through a length clamp and PXXMemMove"
  exit 1
fi

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/frozen_slice.pas" "$work" f

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_frozen"
