#!/bin/sh
# The WAT round-trip, shared by every slice check.
#
#   wat_oracle.sh <pxx> <slice.pas> <workdir> <tag> [extra compiler flags...]
#
# The trailing flags exist for slices whose source needs a unit search path —
# the PAL slice compiles only with -Fulib/rtl/platform/wasi. Without the
# pass-through, calling this with an extra argument compiles the slice WITHOUT
# it, the compile fails, and the only way to keep the caller green is a `|| true`
# that turns the round-trip into a decoration.
#
# Compiles the slice a second time to a .wat, parses it back with wat2wasm, and
# compares the two modules through wasm2wat. The text form is the only readable
# view of what was emitted, and it is worth exactly as much as its agreement
# with the binary — a .wat that names a local it never declares is not an
# oracle, it is a second thing to debug.
#
# It ran on ONE hand-built four-function module for four phases and passed,
# because the two bugs it would have caught (a local-name lookup keyed to "the
# most recently declared function", and an export order that follows function
# order instead of insertion order) both need more than four functions to show.
# Cheap per slice, so every slice pays it.
#
# Compared through wasm2wat rather than with cmp: our body size prefixes are
# padded to a fixed five bytes (the standard placeholder-and-patch technique)
# where wat2wasm emits minimal LEBs, so the two are semantically identical and
# never byte-identical.
set -e
pxx=$1; src=$2; work=$3; tag=$4
shift 4

"$pxx" --target=wasm32 -dWASM_NOMAIN "$@" "$src" "$work/$tag.wat" > /dev/null 2>&1
wat2wasm "$work/$tag.wat" -o "$work/$tag.fromtext.wasm"
wasm-validate "$work/$tag.fromtext.wasm"
wasm2wat "$work/$tag.wasm"          -o "$work/$tag.a.wat"
wasm2wat "$work/$tag.fromtext.wasm" -o "$work/$tag.b.wat"
if diff -u "$work/$tag.a.wat" "$work/$tag.b.wat" > "$work/$tag.d"; then
  echo "ok  .wasm and .wat describe the same module"
else
  echo "FAIL .wat and .wasm disagree"; head -40 "$work/$tag.d"; exit 1
fi
