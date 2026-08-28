#!/bin/sh
# Managed (reference-counted) string ASSIGNMENT on wasm32.
#
# A managed string's slot is pointer-sized, so the WRONG lowering of `s := x`
# is a store instruction that validates, runs, and produces a plausible wrong
# answer — the address of a literal's frozen [len][chars] blob sitting where a
# heap handle belongs, every later read off by eight bytes. So the oracle is
# the NATIVE build, reached through the same frontend, and the diff is the
# primary assertion.
#
# Around it are the assertions a diff cannot make:
#
#   * the MECHANISM — the publish sequence must go through PXXStrFromLit /
#     PXXStrIncRef / PXXStrDecRef. Something that produced the right characters
#     by storing a pointer would pass the diff on this slice and corrupt a
#     longer one;
#   * the three WRITE-POSITION shapes must still refuse BY NAME. IR_LEA of a
#     managed string is position-dependent in the register backends (read =>
#     the handle, write => the slot address) and this target does not model the
#     position; it returns the handle, which is correct only while every write
#     shape refuses somewhere else. That is an argument from what refuses, so
#     it is CHECKED rather than trusted;
#   * a POSITIVE TWIN for that negative: the slice itself must refuse nothing.
#     "These three refuse" passes vacuously on a build where everything
#     refuses, and that is exactly the state this phase started in.
#
# HONEST SCOPE, and it expires mechanically. The wasm32 heap arena still starts
# at address 0 — bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero,
# open — so allocation overlaps the null guard, BSS and the shadow stack, and
# runs off the end of a 128 KB memory at about 128 KB. This slice passes
# because its live set is a handful of short strings that the free list
# recycles inside the first kilobyte. A green tick here means the publish
# sequence is right; it does NOT mean managed strings work at scale. The last
# check below asserts the heap is still broken, so that the day the ticket
# lands this script fails and this paragraph has to be rewritten rather than
# quietly outliving its cause.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-managed.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/managed_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

# NOT piped: a pipeline's exit status is its LAST command's, so a compile
# failure would sail through `| head` under `set -e`.
"$root/compiler/pascal26" --target=wasm32 \
    "$here/managed_slice.pas" "$work/m.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/m.wasm"

# The positive twin of the refusal assertions further down.
if grep -qE '^    (Make|Fill|Local|main\$0) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Make|Fill|Local|main\$0) ' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered — the refusal checks below are"
echo "..  therefore about those shapes and not about a broken build"

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

node "$work/run.js" "$work/m.wasm" > "$work/wasm.txt"
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  literal, Char, frozen, another handle, self-assign, a function"
  echo "..  result, a record field, a var parameter, a loop and the empty"
  echo "..  string; Length in each shape; \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# The MECHANISM. A store that produced the right characters without touching
# the refcount would pass the diff above and corrupt any program that outlives
# one statement.
"$root/compiler/pascal26" --target=wasm32 \
    "$here/managed_slice.pas" "$work/m.wat" > /dev/null 2>&1
for sym in PXXStrFromLit PXXStrIncRef PXXStrDecRef; do
  if ! grep -q "call \$$sym" "$work/m.wat"; then
    echo "FAIL the publish sequence does not call $sym — a managed store is"
    echo "     materialise, publish, release, not a pointer store"
    exit 1
  fi
done
echo "ok  the store is materialise / retain / release, not a pointer store"

# Zero-init of a managed slot, where it is load-bearing: Make's RESULT slot is
# frame memory, and its first `Make := 'one'` reads that slot to find the handle
# it must release. Removing the zeroing makes the diff above TRAP on stale bytes
# left by the caller's writeln — measured — so that diff is already the real
# assertion. This one pins WHERE it happens: in the prologue, before any call,
# because a zeroing that drifted after the first store would still pass a
# whole-body grep while being useless.
if ! awk '/\(func \$Make /,/^  \)/' "$work/m.wat" \
     | sed -n '1,/call /p' \
     | grep -A1 '^ *i32.const 0$' | grep -q '^ *i32.store'; then
  echo "FAIL Make does not zero its managed result slot BEFORE its first call"
  exit 1
fi
echo "ok  a managed slot is zeroed in the prologue, ahead of anything that"
echo "..  could read it as a live handle"

# The three write-position shapes. Each must refuse, and each must refuse BY
# NAME — a generic 'IR op 42' would mean the refusal moved and no longer covers
# what this depends on.
mk() { cat > "$work/neg.pas" <<EOF
program Neg;
var s: string;
begin
$1
end.
EOF
"$root/compiler/pascal26" --target=wasm32 "$work/neg.pas" "$work/neg.wasm" \
    > "$work/neg.txt" 2>&1 || true
}
check_neg() {
  mk "$1"
  if ! grep -qF "$2" "$work/neg.txt"; then
    echo "FAIL '$1' no longer refuses with: $2"
    cat "$work/neg.txt"
    exit 1
  fi
}
check_neg "  s := 'abc'; SetLength(s, 2);" "builtin SetLength"
check_neg "  s := 'abc'; s[1] := 'z';"     "indexing a managed string"
check_neg "  s := 'a'; s := s + 'b';"      '`+` on strings'
echo "ok  SetLength, indexed write and concat still refuse by name — the"
echo "..  three shapes IR_LEA's read-only answer depends on"

# The scope note above, made falsifiable. When the heap ticket lands this
# fails, and the note has to be rewritten rather than outliving its cause.
cat > "$work/heap.pas" <<'EOF'
program HeapBase;
var p: Pointer;
begin
  p := PXXAlloc(64, 8);
  writeln(NativeInt(p));
end.
EOF
"$root/compiler/pascal26" --target=wasm32 "$work/heap.pas" "$work/h.wasm" \
    > /dev/null 2>&1
base=$(node "$work/run.js" "$work/h.wasm")
if [ "$base" -ge 1024 ]; then
  echo "ok  the heap arena now starts at $base, above the null guard —"
  echo "    bug-a-heapmmap-has-no-wasm32-arm... has landed. REWRITE this"
  echo "    script's scope note and re-measure the slice at scale."
  exit 1
fi
echo "ok  heap arena still at $base (< 1024): the scope note above still holds"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/managed_slice.pas" "$work" m

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_managed"
