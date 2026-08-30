#!/bin/sh
# Write/WriteLn of a real on wasm32 -- the spill, not the formatting.
#
# The RTL float writers take the double by ADDRESS: PXXWriteFloatNat(p),
# PXXWriteFloatFixed(p, decimals, width), PXXWriteFloatSci(p, frac, exp). The
# three-way selection off `decs` is shared with every register backend; what
# is this target's own is finding somewhere to put the double that a CALL can
# still point at, since the callee's frame goes below $sp.
#
# The oracle is the native build, so the digits are held to the same RTL that
# produced them -- this is not a float-accuracy test and the values are not
# this backend's to get right.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-floatwrite.$$
mkdir -p "$work/sandbox"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/floatwrite_slice.pas" "$work/prog" >/dev/null
"$work/prog" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/floatwrite_slice.pas" "$work/w.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/w.wasm"

if grep -qE '^    (Half|main\$[0-9])' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Half|main\$[0-9])' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

node --no-warnings "$here/wasihost.js" "$work/w.wasm" "$work/sandbox" \
    > "$work/wasm.txt"

# Two empty files diff clean, and a refused float write produces no line at
# all. Assert on output the slice actually emits before believing the diff.
grep -q '^3.7500$' "$work/native.txt" || {
  echo "FAIL the oracle did not produce the fixed-form row -- the harness,"
  echo "     not the backend:"; cat "$work/native.txt"; exit 1; }

if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  all three writers (native / fixed / scientific), a field width, a"
  echo "..  negative, zero, 1e20 and 1e-20, a tySingle (whose scientific digit"
  echo "..  split differs), TWO floats live in one WriteLn, and a float whose"
  echo "..  value is a call -- the last two being what a frame-reserved"
  echo "..  scratch would get wrong"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

echo "PASS check_floatwrite"
