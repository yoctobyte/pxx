#!/bin/sh
# Frac (-205) and Int (-206) on wasm32: the two float intrinsics that return a
# REAL, as against Trunc/Round which return an integer.
#
# On wasm both are f64.trunc and there is no rounding question, so what this
# actually guards is the three ways the arm can be wrong around the edges:
# the sign of the result for a negative argument, the tySingle narrowing (a C
# `(float)x` cast lowers to Int(x), and riscv32 shipped that reading double
# bits as a single), and a nested Frac clobbering the outer one's saved copy.
#
# Values are printed as scaled INTEGERS: writing a float is a separate,
# still-open gap on this target, and encoding the result sidesteps it without
# weakening the assertion.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-floatint.$$
mkdir -p "$work/sandbox"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/floatint_slice.pas" "$work/prog" >/dev/null
"$work/prog" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/floatint_slice.pas" "$work/w.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/w.wasm"

if grep -qE '^    (Show|main\$[0-9])' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Show|main\$[0-9])' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

node --no-warnings "$here/wasihost.js" "$work/w.wasm" "$work/sandbox" \
    > "$work/wasm.txt"

# Two empty files diff clean. Assert on output the slice actually emits.
grep -q '^neg    int=-30000 frac=-7500$' "$work/native.txt" || {
  echo "FAIL the oracle did not produce the negative row -- the harness, not"
  echo "     the backend:"; cat "$work/native.txt"; exit 1; }

if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  Int/Frac of a positive, a negative, zero, a pure fraction, a value"
  echo "..  past 32 bits, an INTEGER argument (promoted), a tySingle result"
  echo "..  (narrowed), and a Frac nested inside a Frac"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

echo "PASS check_floatint"
