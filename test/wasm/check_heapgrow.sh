#!/bin/sh
# The wasm32 heap past its first megabyte -- memory.grow, reached from Pascal.
#
# HeapMmap's wasm arm used to hand out one fixed 1 MiB BSS arena and return -1
# for every request after it: a hard ceiling no other target has, and the reason
# compiler.pas under WASI trapped inside PXXAlloc three frames below
# EnsureTokCapacity before it had parsed anything. It now calls memory.grow,
# reached through `external 'wasm' name 'memory.grow'` -- a reserved module name
# the backend reads as THIS MACHINE and lowers to the instruction inline rather
# than to an import, so the module still demands nothing of its host.
#
# What that can get wrong, and what the slice is shaped to catch: memory.grow
# returns the PREVIOUS SIZE IN PAGES -- not the new size, not a byte address --
# so a base computed from the wrong one lands inside memory already in use, and
# the corruption then surfaces somewhere unrelated. Every block is written and
# ALL of them re-read after later growth, so an overlapping base is caught as a
# wrong byte rather than as a plausible-looking total. The zero-init contract is
# checked too: on this target it is inherited from wasm's guarantee about new
# pages rather than from a memset, so it is exactly the kind of property that
# holds by accident until it doesn't.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-heapgrow.$$
mkdir -p "$work/sandbox"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/heapgrow_slice.pas" "$work/prog" >/dev/null
"$work/prog" > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/heapgrow_slice.pas" "$work/w.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/w.wasm"

if grep -qE '^    main\$[0-9]' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    main\$[0-9]' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

# The instruction must NOT appear as an import -- that is the whole claim of the
# reserved module name, and an import named memory.grow would make every module
# that allocates refuse to instantiate on a host that supplies nothing.
if wasm-objdump -x "$work/w.wasm" | grep -q 'memory\.grow'; then
  echo "FAIL memory.grow was emitted as an import, not as an instruction:"
  wasm-objdump -x "$work/w.wasm" | grep 'memory\.grow'
  exit 1
fi
echo "ok  memory.grow is an instruction, not an import"

node --no-warnings "$here/wasihost.js" "$work/w.wasm" "$work/sandbox" \
    > "$work/wasm.txt"

# A build that failed every allocation prints alloc_failed_at and halts; one
# that never grew would too. Assert the oracle got all the way through.
grep -q '^done$' "$work/native.txt" || {
  echo "FAIL the oracle did not finish -- the harness, not the backend:"
  cat "$work/native.txt"; exit 1; }

if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build:"
  echo "..  48 blocks of 256 KB (12 MB, twelve times the old ceiling), every"
  echo "..  one written then re-read after later growth, and fresh memory zero"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

echo "PASS check_heapgrow"
