#!/bin/sh
# `x in [...]` on wasm32 — set membership over a constant literal.
#
# THE ORACLE IS THE NATIVE BUILD. This one needs no slope probe and no
# reuse-forcing control: `in` allocates nothing, owns nothing and reads no
# refcount, so every way it can be wrong is a wrong ANSWER and the diff is the
# whole instrument. Saying that out loud is the point — the previous two slices
# each needed a second instrument, and the reason this one does not is a
# property of the operator, checked rather than assumed.
#
# 267 of compiler.pas's 431 remaining refusal lines were this, and that number
# is a FIRST-refusal count: bodies stop at their first unsupported thing, so it
# is a ranking of what programs reach, not of what they need. It was 68 before
# dynamic arrays landed, with nothing about `in` changing.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-set.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/set_slice.pas" "$work/native" > /dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 "$here/set_slice.pas" "$work/s.wasm" \
    > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/s.wasm"

if grep -qE '^    main\$[0-9]' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    main\$[0-9]' "$work/cov.txt"
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
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  scalars, ranges, both orders of a mixed literal, inclusive"
  echo "..  boundaries, a single-element range, the empty set, Char, an enum,"
  echo "..  and a 64-bit value against small members; \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# --- BRANCHLESS, asserted because it is the design and not an accident -------
# Every register backend jumps: i386 emits jl/jg around each range, arm32 and
# aarch64 the same shape. wasm has no flags to accumulate into but it has an
# operand stack, so the whole literal is one expression — i32.or over the
# membership tests. If a future change reintroduces control flow here it is a
# regression in the thing that made this arm short, and nothing else would say
# so. `br` covers br_if and br_table too, since the WAT spells them all with it.
# A SEPARATE program, because the slice's own main$0 is full of for-loops and
# control flow there proves nothing. This one contains exactly one `in` and no
# other statement that could branch.
cat > "$work/one.pas" <<'EOF'
program One;
var i: Integer;
begin
  i := 5;
  writeln(i in [1, 3..7, 9]);
end.
EOF
"$root/compiler/pascal26" --target=wasm32 "$work/one.pas" "$work/one.wasm" \
    > /dev/null 2>&1
if wasm2wat "$work/one.wasm" | sed -n '/(func \$main\$0$/,/^  (func /p' \
     | grep -qE '^\s+(if|loop)\b|^\s+br'; then
  echo 'FAIL the `in` lowering emits control flow. It is meant to be one'
  echo "     expression — i32.or over the tests — which is what makes this arm"
  echo "     shorter than every register backend's. Got:"
  wasm2wat "$work/one.wasm" | sed -n '/(func \$main\$0$/,/^  (func /p' \
     | grep -E '^\s+(if|loop)\b|^\s+br' | head -5
  exit 1
fi
echo "ok  the lowering is branchless — one expression, no if/loop/br, where"
echo "..  every register backend jumps around each range"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/set_slice.pas" "$work" s

echo "PASS check_set"
