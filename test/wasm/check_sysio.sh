#!/bin/sh
# The sys* intrinsic family (sysopen / sysread / syswrite / sysclose /
# sysfchmod) on wasm32, against the native build.
#
# Why this family and not another: these five ARE the compiler's own output
# path -- every file compiler.pas writes it writes with them -- so they are the
# gate between "wasm32 lowers a program" and "wasm32 could host the compiler".
#
# On a register target the backend emits a raw `syscall` instruction. wasm has
# no such instruction and no ambient filesystem: WASI is capability-based, so a
# path is resolved against the preopen table the host handed the module. The
# translation lives in compiler/builtin/wasibackend.pas -- NOT in the PAL,
# because compiler.pas deliberately links no PAL -- and is pulled in only when
# TargetArch = TARGET_WASM32 (pasparser_prog.inc), never ambiently.
#
# What that design could get wrong, and what this slice is shaped to catch:
#  - the path argument.  A managed AnsiString's handle already IS the
#    nul-terminated pointer; a frozen string is length-prefixed and needs a NUL
#    written past its end.  Both shapes appear here (`path` is assigned twice).
#  - the errno SIGN.  WASI returns a positive errno; POSIX open returns -1.  A
#    missing file that comes back positive is a valid fd downstream, which is
#    silent corruption rather than a failure -- hence missing_lt0.
#  - the statement-position drop.  sysfchmod/sysclose are functions used as
#    statements; builtin arms own their own stack discipline and return before
#    the ordinary drop, so a missing drop leaves the value on the operand stack
#    and the MODULE FAILS TO VALIDATE.  wasm-validate below is that assertion.
#  - the data actually landing.  Matching stdout while writing nothing to the
#    file would pass a stdout-only diff, so the sandbox file is compared too.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-sysio.$$
mkdir -p "$work/nsand" "$work/wsand"
trap 'rm -rf "$work"' EXIT

"$root/compiler/pascal26" "$here/sysio_slice.pas" "$work/prog" >/dev/null
( cd "$work/nsand" && "$work/prog" ) > "$work/native.txt"

"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/sysio_slice.pas" "$work/w.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/w.wasm"

if grep -qE '^    (main\$[0-9]|PXXWasi)' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (main\$[0-9]|PXXWasi)' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

node --no-warnings "$here/wasihost.js" "$work/w.wasm" "$work/wsand" \
    > "$work/wasm.txt"

# Assert the oracle actually exercised the path before believing any diff: a
# native build that failed every open prints open_ok=FALSE throughout and would
# diff clean against a wasm build that did the same.
grep -q '^open_ok=TRUE$' "$work/native.txt" || {
  echo "FAIL the oracle could not open its own file -- the harness, not the backend:"
  cat "$work/native.txt"; exit 1; }

if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines)"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# stdout can agree while the file never lands -- compare what reached the disk.
if diff -u "$work/nsand/intrin.txt" "$work/wsand/intrin.txt"; then
  echo "ok  the file the wasm build wrote matches the native one byte for byte"
else
  echo "FAIL the sandbox file diverges"; exit 1
fi

echo "PASS check_sysio"
