#!/bin/sh
# The `LoadFile` builtin (IR_CALL with proc index -100) on wasm32.
#
# Every other target lowers this to builtinheap's PXXStrLoadFile. That body is
# unreachable on wasm: it is written over PXXSysOpenRO / PXXSysLseek /
# PXXSysRead / PXXSysClose, whose {$if} chain has no wasm arm and correctly
# answers -1 rather than inventing an fd. Giving it one would mean a THIRD copy
# of the WASI preopen model inside builtinheap, or a builtinheap -> wasibackend
# dependency that drags the preopen imports into every wasm32 module that merely
# allocates a string. So the wasm arm of that one algorithm lives in
# compiler/builtin/wasibackend.pas as PXXWasiLoadFile, and the backend picks the
# callee by target.
#
# What that could get wrong, and what this slice is shaped to catch:
#  - an EMPTY file coming back as nil rather than as an empty string. nil is how
#    the helper reports "could not open"; the two are different answers and the
#    caller can only tell them apart if the empty case is a real string.
#  - the destination's OLD handle. The store must release it, and must release
#    it LAST -- `LoadFile(p, s)` where s holds the only reference to the old
#    bytes must not free them before the new handle is stored. Three loads into
#    one destination is the shape that shows a double-free or a use-after-free.
#  - the loaded string not being an ordinary managed string afterwards, so it is
#    concatenated once at the end.
#  - the path operand's two shapes. It goes through WasmEmitPathArg, the same
#    helper the sys* family uses, so both are exercised by check_sysio.sh too.
#
# The slice writes its own inputs, so both runs read identical bytes with no
# fixture for the harness to install. Note the two-arg sysopen passes mode 0 --
# a file it creates is unreadable even to the process that made it until
# sysfchmod runs, which is why the compiler's output path always pairs them.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-loadfile.$$
mkdir -p "$work/nsand" "$work/wsand"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/loadfile_slice.pas" "$work/prog" >/dev/null
( cd "$work/nsand" && "$work/prog" ) > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/loadfile_slice.pas" "$work/w.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/w.wasm"

if grep -qE '^    (main\$[0-9]|MakeFile|PXXWasi)' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (main\$[0-9]|MakeFile|PXXWasi)' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

node --no-warnings "$here/wasihost.js" "$work/w.wasm" "$work/wsand" \
    > "$work/wasm.txt"

# Both builds returning 0 for everything diff clean against each other. Assert
# the oracle actually read a file before believing the diff.
grep -q '^small_len=11$' "$work/native.txt" || {
  echo "FAIL the oracle loaded nothing -- the harness, not the backend:"
  cat "$work/native.txt"; exit 1; }

if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  an ordinary load, an EMPTY file (empty string, not nil), an absent"
  echo "..  one, three reloads into one destination, a 300-byte file, and the"
  echo "..  result concatenated to prove it is an ordinary managed string"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

echo "PASS check_loadfile"
