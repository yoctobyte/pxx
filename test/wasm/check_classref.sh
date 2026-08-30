#!/bin/sh
# IR_CLASSREF (op 39) on wasm32 -- the metaclass VALUE.
#
# `TFoo` used as a value is the address of the class's RTTI blob, which is what
# `is`, `as`, a class-of variable and ClassType all evaluate to. The register
# backends emit it as a code->data relocation against a sentinel patched after
# EmitRTTI; this target has no code->data fixups at all, so it reaches the blob
# through a data cell instead -- the SAME cell table the record-descriptor path
# already uses, since both want UClsRTTIOff[ci] and neither can know it while
# bodies are being emitted.
#
# What that design could get wrong, and what this slice is shaped to catch: a
# cell resolved to the wrong class (every `is` still answers, just wrongly), and
# the memo handing two customers the same cell for different classes.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-classref.$$
mkdir -p "$work/sandbox"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/classref_slice.pas" "$work/prog" >/dev/null
"$work/prog" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/classref_slice.pas" "$work/w.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/w.wasm"

if grep -qE '^    (T(Base|Mid|Leaf)\.|main\$[0-9])' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (T(Base|Mid|Leaf)\.|main\$[0-9])' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

node --no-warnings "$here/wasihost.js" "$work/w.wasm" "$work/sandbox" \
    > "$work/wasm.txt"

# A cell resolved to a single wrong class makes every `is` answer TRUE, and two
# all-TRUE files diff clean against each other but not against native. Assert a
# known FALSE exists before believing the diff.
grep -q '^b is TMid   FALSE$' "$work/native.txt" || {
  echo "FAIL the oracle produced no FALSE row -- the harness, not the backend:"
  cat "$work/native.txt"; exit 1; }

if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  \`is\` up and down a three-deep chain and across a sibling; through"
  echo "..  a base-typed reference; \`as\` at two levels with virtual dispatch"
  echo "..  after it; and a class-of variable compared against two metaclasses"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

echo "PASS check_classref"
