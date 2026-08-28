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
#   * the LEAK, run against wasm ALONE. An operand that owned its reference —
#     a call result, a nested concat — must be released after the RTL call, and
#     a leak changes no output whatsoever, so the observable is the heap. The
#     probe below allocates a size the loop never frees, so every call bumps,
#     and asserts the advance does not scale with the iteration count.
#
# Why wasm alone, when everything else here is diffed against native: THE
# NATIVE BUILD LEAKS THIS. x86-64 releases an owned managed-string operand
# after a concat and not after a comparison — 40 bytes per evaluation of
# `f(x) = 'lit'`, measured at 401032 bytes over 10000 iterations against 1032
# on wasm and 0 under FPC, and present on x86-64 alone: the four cross backends
# all carry the release at all three sites. Filed as
# bug-a-a-string-function-result-in-a-comparison-leaks-on-x86-64. Diffing a
# leak figure against a build with an open leak would assert the bug, so the
# check asserts the PROPERTY on wasm and separately asserts that native still
# has the bug — which makes this paragraph expire the day the ticket lands.
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

# The other half of that claim, and its expiry. Native must still leak; when it
# stops, this fails and the note at the top has to be rewritten.
mkleak 1000
"$root/compiler/pascal26" "$work/leak.pas" "$work/leakn" > /dev/null
n1=$("$work/leakn")
mkleak 9000
"$root/compiler/pascal26" "$work/leak.pas" "$work/leakn" > /dev/null
n2=$("$work/leakn")
if [ "$n1" = "$n2" ]; then
  echo "ok  the NATIVE build no longer leaks either ($n1 at both counts) —"
  echo "    bug-a-a-string-function-result-in-a-comparison-leaks-on-x86-64 has"
  echo "    landed. Rewrite this script's note and diff the figure again."
  exit 1
fi
echo "ok  native still leaks it ($n1 -> $n2), so the wasm figure above is a"
echo "..  property and not a copy of the oracle — the reason it is not diffed"

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
body() { awk '/\(func \$main\$0/,/^  \)/' "$1"; }
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
