#!/bin/sh
# Forwarding a `var` parameter onward as another routine's `var` argument, on
# wasm32.
#
# THE NODE IS AMBIGUOUS AND ONLY THE CONSUMER RESOLVES IT. IR_LEA on a scalar
# managed string is position-dependent — read position yields the HANDLE, write
# position yields the SLOT's address — and the lowering emits the same
# `lea [sym=p]` for every use of a `var s: AnsiString` parameter: `Length(p)`,
# `p[1]`, `p[1] := c`, and forwarding `p` into another routine's `var`. Four
# consumers, one node. The argument emitter walked its operands in read position
# unconditionally, which is right for a by-value parameter and exactly wrong for
# a by-reference one, so the callee received the string's DATA pointer where its
# slot address belonged.
#
# It validates. Both are i32, the operand stack balances, and every body reports
# as lowered — which is why this was found by running the compiler under WASI
# and not by any assertion in this suite.
#
# WHY A DIFF IS THE PRIMARY ASSERTION, and not a grep for the missing load. The
# defect has two arms and only one of them is loud:
#
#   * the callee RESIZES through the reference — PXXStrSetLen is handed four
#     characters of text as a length word and the module traps;
#   * the callee PUBLISHES a new handle through it — a valid handle is stored
#     into the caller's character bytes. Nothing traps. The caller reads back a
#     plausible wrong string.
#
# A structural check tuned to the first arm would have gone green on the second.
# The native build is the oracle for both.
#
# THE READ TWINS ARE THE OTHER HALF OF THE ASSERTION and they are not padding.
# The fix makes a by-reference argument a write position; the way to get that
# wrong in the other direction is to make EVERY argument one, which breaks
# `ByValue(p)`, `Length(p)` and `p[1]` while leaving every forward correct. The
# slice runs all of them, so this check fails in both directions rather than
# only the one that was observed.
#
# SCOPE, stated because the slice's own coverage note cannot: this is about
# scalar managed strings. A `var` dynamic array reaches IR_LEA through the arm
# above it, which ignores the position flag on purpose, and is not exercised
# here.
#
# Found by: bug-wasm-hosted-compiler-faults-on-a-garbage-string-handle-in-the-
# unit-resolver. The compiler's unit resolver holds a local `path`, hands it to
# PyTryHostHeader as `var path`, which hands it on to ConcatThree as `var dst` —
# and the handle PXXStrSetLen then read was 0x2f62696c, little-endian ASCII
# "lib/": the first four characters of the `lib/rtl/...` path the slot was
# supposed to be pointing at rather than holding.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-varparam.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/varparam_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`.
"$root/compiler/pascal26" --target=wasm32 \
    "$here/varparam_slice.pas" "$work/v.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/v.wasm"

# The positive twin: a slice where everything refuses would pass every
# assertion below vacuously.
if grep -qE '^    (Resize|Publish|ByValue|Fwd|Pub|Deref|Len|Idx|IdxW|Hop1|Hop2) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Resize|Publish|ByValue|Fwd|Pub|Deref|Len|Idx|IdxW|Hop1|Hop2) ' "$work/cov.txt"
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

node "$work/run.js" "$work/v.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  a var string param forwarded into another var param (resize, and"
  echo "..  the silent publish arm), two hops deep, through a VIRTUAL call, and"
  echo "..  the read twins — by-value use, Length, an index read and an index"
  echo "..  write — that a fix in the other direction would break"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# The forward really reached the CALLER's variable, asserted on the value rather
# than on the instruction sequence. `fwd=xyz` is only three characters long
# because Resize's SetLength published a shorter handle into the caller's slot;
# a callee that wrote through the data pointer instead leaves the caller holding
# its original eight-character handle, and the tell is the LENGTH, not the text.
if ! grep -qx 'fwd=xyz' "$work/wasm.txt"; then
  echo "FAIL the callee's SetLength did not reach the caller's slot"
  exit 1
fi
if ! grep -qx 'final-len=3' "$work/wasm.txt"; then
  echo "FAIL the caller's string is still its original length after a var"
  echo "     forward resized it — the reference did not reach the slot"
  exit 1
fi
if ! grep -qx 'pub=published' "$work/wasm.txt"; then
  echo "FAIL the SILENT arm: a handle published through a var forward did not"
  echo "     reach the caller's slot. This one does not trap — it writes a"
  echo "     handle into the caller's character bytes."
  exit 1
fi
echo "ok  the reference reached the caller's slot in both arms — the resize"
echo "..  (witnessed by the LENGTH, not the text) and the silent publish"

# The read twins, named individually so a failure says which direction the
# position model fell over in.
for want in byval=abcdefgh len=8 idx=ab idxw=Qbcdefgh; do
  if ! grep -qx "$want" "$work/wasm.txt"; then
    echo "FAIL a READ of a var string parameter is wrong: expected [$want]."
    echo "     A by-reference argument is a write position; every OTHER use of"
    echo "     the same IR_LEA node is not."
    exit 1
  fi
done
echo "ok  the read twins are intact — by-value use, Length, index read and"
echo "..  index write still get the handle, not the slot"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/varparam_slice.pas" "$work" v

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_varparam"
