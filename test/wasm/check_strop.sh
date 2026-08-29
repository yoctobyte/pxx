#!/bin/sh
# Managed-string CONCATENATION and COMPARISON on wasm32.
#
# Neither is an instruction on any target. Both operate on a pointer-shaped
# type, so the WRONG lowering validates and runs: `a = b` as an i32.eq of two
# handles asks "the same buffer" where Pascal asked "the same characters" and
# is right about half the time. Ordered comparison is the one with history —
# it reached no cross backend for a long while, so `'zzz' < 'aaa'` answered by
# ALLOCATION ORDER on four targets at once
# (bug-a-ordered-string-comparison-of-a-parameter-compares-handles-on-every-cross-target).
#
# So the native build is the oracle and the diff is the primary assertion.
# Around it:
#
#   * the MECHANISM must be the three RTL calls, asserted BOTH WAYS. A module
#     with no string operators must contain none of them — otherwise the
#     positive check would pass on a build that emits the RTL unconditionally,
#     which is a check that cannot fail;
#   * the LEAK, on BOTH builds. An operand that owned its reference — a call
#     result, a nested concat — must be released after the RTL call, and a leak
#     changes no output whatsoever, so the observable is the heap. The probe
#     below allocates a size the loop never frees, so every call bumps, and
#     asserts the advance does not scale with the iteration count.
#
# That last one used to run against wasm ALONE, because the native build leaked
# it: x86-64 released an owned managed-string operand after a concat and not
# after a comparison, 40 bytes per evaluation of `f(x) = 'lit'`. It was found
# HERE, by the wasm figure having nothing to diff against, and filed as
# bug-a-a-string-function-result-in-a-comparison-leaks-on-x86-64. It landed in
# 0d91dc88f (re-verified 0571f4f9e), and both builds are now flat at 1032 bytes
# for 1000, 9000 and 100000 iterations alike, so the leak is diffed against the
# oracle like everything else here and the property check is the second half.
#
# Note what the old note cost. It was written to avoid encoding a bug and it
# encoded one anyway — as the FIGURE it compared against. A workaround that
# names a defect's magnitude goes stale exactly when the defect is fixed, and it
# goes red in the direction that reads as a new regression. The `exit 1` below
# was aimed at that: it fired the day the fix landed and said, in the failure
# text, which paragraph to rewrite. Prefer that to a number in a comment.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-strop.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

cp "$here/wasmhost.js" "$work/"

"$root/compiler/pascal26" "$here/strop_slice.pas" "$work/native" >/dev/null
"$work/native" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 \
    "$here/strop_slice.pas" "$work/s.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/s.wasm"

if grep -qE '^    (Make|main\$0) ' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Make|main\$0) ' "$work/cov.txt"
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

node "$work/run.js" "$work/s.wasm" > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  concat over handle/literal/Char-left/Char-right/frozen-both-ways/"
  echo "..  owned-temp/chained/empty; all six comparisons including the"
  echo "..  ordered ones and the prefix case; and the arena advance, \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# --- the leak probe ---------------------------------------------------------
# 1024 bytes is a size the loop never allocates and therefore never frees, so
# every call bumps the arena rather than popping a free list. The advance is
# then (one probe block) + (whatever the loop failed to release), and running
# it at two iteration counts separates the constant from the per-iteration
# term. A build that releases everything gives the SAME number at both counts.
mkleak() { cat > "$work/leak.pas" <<EOF
program Leak;
var i: Integer; b: Boolean; u, s, t: string; p1, p2: Pointer;
function Name: string;
begin
  Name := 'one';
end;
begin
  s := 'ab'; t := 'cd';
  for i := 1 to 100 do begin b := Name = 'one'; u := s + Name; end;
  p1 := PXXAlloc(1024, 8);
  for i := 1 to $1 do begin b := Name = 'one'; u := s + Name; end;
  p2 := PXXAlloc(1024, 8);
  writeln(NativeInt(p2) - NativeInt(p1));
end.
EOF
}
leakrun() {   # $1 = iterations -> prints the advance for the wasm build
  mkleak "$1"
  "$root/compiler/pascal26" --target=wasm32 "$work/leak.pas" "$work/leak.wasm" \
      > /dev/null 2>&1
  node "$work/run.js" "$work/leak.wasm"
}
a1=$(leakrun 1000)
a2=$(leakrun 9000)
if [ "$a1" != "$a2" ]; then
  echo "FAIL an owned string operand is leaked: 1000 iterations advance the"
  echo "     heap by $a1 bytes and 9000 by $a2 — a released temporary would"
  echo "     give the same number at both counts"
  exit 1
fi
echo "ok  1000 and 9000 iterations both advance the heap by $a1 bytes — every"
echo "..  owned operand temporary is released, in the compare AND the concat"

# The oracle half. Native must be flat too, AND must agree with wasm: since
# 0d91dc88f the figure is comparable, so a wasm-side regression that happened to
# be flat at both counts — a constant over-allocation, say — is caught by the
# diff rather than passing the slope test. Two assertions, not one: flat, and
# equal. A build that leaked identically on both targets would satisfy the
# second alone, and one that over-allocated identically would satisfy the first.
mkleak 1000
"$root/compiler/pascal26" "$work/leak.pas" "$work/leakn" > /dev/null
n1=$("$work/leakn")
mkleak 9000
"$root/compiler/pascal26" "$work/leak.pas" "$work/leakn" > /dev/null
n2=$("$work/leakn")
if [ "$n1" != "$n2" ]; then
  echo "FAIL the NATIVE build leaks an owned string operand again: 1000"
  echo "     iterations advance the heap by $n1 bytes and 9000 by $n2. This is"
  echo "     bug-a-a-string-function-result-in-a-comparison-leaks-on-x86-64,"
  echo "     which landed in 0d91dc88f — check whether it has been reverted."
  exit 1
fi
if [ "$n1" != "$a1" ]; then
  echo "FAIL the two builds disagree about the advance: native $n1, wasm $a1."
  echo "     Both are flat, so neither is leaking per-iteration, but one is"
  echo "     allocating a different fixed amount than the other for the same"
  echo "     program — a constant a slope test cannot see."
  exit 1
fi
echo "ok  the native build is flat at $n1 too, and the two agree exactly, so"
echo "..  the figure is diffed against the oracle and not merely self-consistent"

"$root/compiler/pascal26" --target=wasm32 \
    "$here/strop_slice.pas" "$work/s.wat" > /dev/null 2>&1
cat > "$work/nostr.pas" <<'EOF'
program NoStr;
var i: Integer;
begin
  i := 40 + 2;
  writeln(i);
end.
EOF
"$root/compiler/pascal26" --target=wasm32 "$work/nostr.pas" "$work/n.wat" \
    > /dev/null 2>&1
# Scoped to $main$0 — the program's own body — and NOT to the whole module.
# Module-wide, the negative half is a lie: the RTL's own PXXVarBinOp calls
# PXXStrConcat, so every module that lowers the variant engine contains the
# symbol whatever the program does. The whole-module version of this check
# passed while it was written, because before this phase PXXVarBinOp was itself
# refused and its body was `unreachable` — a baseline that the very change
# being tested invalidated. Same lesson as the abi.inc grep calibrated against
# an empty result: a negative control has to be measured on the tree the check
# will actually run on, not on the one it was written against.
# NOTE the trailing \$ in every func pattern below. A WAT function identifier
# is name + '$' + slot (unconditionally — Pascal names are not unique and WAT
# identifiers must be), so `\(func \$Make ` with a trailing SPACE stopped
# matching the day the slot suffix landed and this check failed on correct
# code. A bare prefix would match again but would also match $MakeOther;
# anchoring on the separator is what makes the pattern mean "this function".
body() { awk '/\(func \$main\$0\$/,/^  \)/' "$1"; }
for sym in PXXStrConcat PXXStrEq PXXStrCmp3; do
  if ! body "$work/s.wat" | grep -q "call \$$sym"; then
    echo "FAIL the slice's own body does not call $sym — concat and compare"
    echo "     are RTL calls, and something else is producing these answers"
    exit 1
  fi
  if body "$work/n.wat" | grep -q "call \$$sym"; then
    echo "FAIL a program with no string operators calls $sym in its own body,"
    echo "     so the positive check above proves nothing about this lowering"
    exit 1
  fi
done
echo "ok  the three RTL calls appear in the slice's own body and in no body"
echo "..  that lacks string operators — both directions, neither vacuous"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/strop_slice.pas" "$work" s

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_strop"
