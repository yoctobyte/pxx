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
#   * a POSITIVE TWIN for the negatives: the slice itself must refuse nothing.
#     "These refuse" passes vacuously on a build where everything refuses, and
#     that is exactly the state this phase started in.
#
# THE REFUSAL LIST IS GONE, and how it went is the point. It listed the write
# positions — SetLength and `s[i] := c` — because IR_LEA of a managed string
# answered HANDLE unconditionally, which is right only while no write can
# reach it. That was an argument from what refuses, so it was checked rather
# than trusted, and it failed twice.
#
# The FIRST failure was a mistake in the list: concatenation was in it because
# it refused, not because it was a write position, and slice 2 exposed that a
# list assembled from "what currently refuses" rather than from "what this
# argument needs" contains everything that happens to be missing.
#
# The SECOND failure was the list working exactly as designed. Slice 3 lowered
# both remaining entries, so the check went red on a correct change — which is
# what it was for. The response is NOT to trim the list to green: with both
# entries gone there is no argument left to support, and a trimmed list would
# have been an empty assertion sitting under a paragraph claiming a property
# the build no longer has. The argument was REPLACED. This target now models
# the position with InLValueWrite, the way the other four backends do, and the
# assertion that it does — PXXStrUnique present in write position, absent in
# read — lives in check_index.sh, which owns those shapes.
#
# What still guards it HERE is the diff above, and not by accident: removing
# the write arm of IR_LEA makes this slice TRAP rather than diverge (measured
# — a store lands in the handle slot and scope exit releases the wreckage), so
# the read-position answer this script depends on is load-bearing in its own
# output. That is a stronger guard than the refusal list ever was, because it
# fails on the mechanism rather than on the mechanism's absence elsewhere.
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
echo "ok  every routine in the slice lowered — the mechanism checks below are"
echo "..  therefore about real code and not about a broken build"

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
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
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
# NOTE the trailing \$ in every func pattern below. A WAT function identifier
# is name + '$' + slot (unconditionally — Pascal names are not unique and WAT
# identifiers must be), so `\(func \$Make ` with a trailing SPACE stopped
# matching the day the slot suffix landed and this check failed on correct
# code. A bare prefix would match again but would also match $MakeOther;
# anchoring on the separator is what makes the pattern mean "this function".
if ! awk '/\(func \$Make\$/,/^  \)/' "$work/m.wat" \
     | sed -n '1,/call /p' \
     | grep -A1 '^ *i32.const 0$' | grep -q '^ *i32.store'; then
  echo "FAIL Make does not zero its managed result slot BEFORE its first call"
  exit 1
fi
echo "ok  a managed slot is zeroed in the prologue, ahead of anything that"
echo "..  could read it as a live handle"

# The read-position answer, asserted directly rather than through what refuses.
# Reading a managed string must NOT clone it: PXXStrUnique is the write-side
# call, and its appearance in a body that only reads would mean the position
# model had collapsed to "always write" — which is invisible in output, since
# cloning a string you are about to read gives the right characters and merely
# leaks. Scoped to this slice's own bodies: a module-wide grep would start
# answering about the RTL the moment anything in it uses the routine, which is
# the exact way check_strop's negative control went vacuous.
if awk '/\(func \$(Make|Fill|Local|main\$0)\$/,/^  \)/' "$work/m.wat" \
     | grep -q 'call \$PXXStrUnique'; then
  echo "FAIL a read of a managed string clones it — PXXStrUnique appears in a"
  echo "     body of this slice, which only reads. Read position must hand back"
  echo "     the handle."
  exit 1
fi
echo "ok  reading a managed string does not clone it — the write-side call is"
echo "..  absent from every body here (check_index.sh owns the positive half)"

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

# --- the retain, witnessed WITHOUT relying on copy-on-write ------------------
# The diff above already catches a missing retain, because a string's refcount
# is READ by the code under test: copy-on-write asks "am I sole owner?" before
# every write, so a too-low count makes the next write mutate a buffer it should
# have cloned, and the slice's aliasing lines show it.
#
# That coverage is a property of the CURRENT SEMANTICS, not of the type, and it
# is exactly the kind that disappears without a sound. Dynamic arrays used to
# have copy-on-write too; IR_DYNUNIQUE's clone was deleted when
# decide-dynamic-array-value-vs-reference-semantics settled on FPC reference
# semantics. At that moment every dyn-array test that had been witnessing a
# too-low refcount through the diff silently stopped witnessing it, and nothing
# in any output changed. A suite written under COW became an uncovered suite by
# a design decision made elsewhere.
#
# So this assertion does not go through COW at all. It aliases, drops one
# reference, forces the allocator to hand the block to someone else, and reads
# through the surviving name. It costs one allocation and it is the witness that
# survives a semantics change in either direction — which is the only reason to
# have it when the diff already passes.
cat > "$work/retain.pas" <<'EOF'
program Retain;
var s, t, u: string; i: Integer;
begin
  s := 'abcdefghijklmnop';
  t := s;              { shares; the refcount must become 2 }
  t := '';             { drops t's reference — must NOT free the block }
  u := '';
  for i := 1 to 16 do u := u + 'Z';   { same size: reuses the block if freed }
  writeln(s);
end.
EOF
"$root/compiler/pascal26" --target=wasm32 "$work/retain.pas" "$work/retain.wasm" \
    > /dev/null 2>&1
got=$(node "$work/run.js" "$work/retain.wasm")
if [ "$got" != "abcdefghijklmnop" ]; then
  echo "FAIL a shared string was freed while another name still held it."
  echo "     Expected [abcdefghijklmnop], got [$got]. If the answer is sixteen"
  echo "     Z's the block was released on the second name's reassignment and"
  echo "     handed straight back out."
  exit 1
fi
echo "ok  a shared string survives the other name being reassigned, proven by"
echo "..  forcing the allocator to reuse the block rather than by copy-on-write"
echo "..  — a witness that outlives the semantics the diff's version rests on"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/managed_slice.pas" "$work" m

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_managed"
