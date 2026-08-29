#!/bin/sh
# WASI file operations on wasm32: open / read / write / seek / close / sync,
# the three single-path operations, rename, and the clocks.
#
# THE ORACLE IS THE NATIVE BUILD, and the harness is node's own WASI — an
# independent preview1 implementation with a real filesystem. That pairing is
# the point: the shim this project wrote (wasmhost.js) would agree with this
# backend by construction, including where both are wrong, and it has no
# filesystem to disagree about.
#
# What a happy-path "does writeln to a file work" would NOT catch, and each of
# these is a way a WASI backend differs from a posix one:
#
#   * PATH RESOLUTION. There is no open(2). Every path resolves against the
#     table of directories the host preopened and the host is handed the
#     remainder. A path under no grant must be ENOENT.
#   * ERRNO NUMBERING. WASI's errno list is alphabetical and Linux's is not,
#     so WASI 2 is EACCES where Linux 2 is ENOENT. Both are non-zero, so
#     anything that only asks "did it fail" agrees with a build that turns
#     every missing file into a permission error.
#   * RIGHTS. An fd carries the rights it was opened with and refuses anything
#     else with ENOTCAPABLE. Too few gives an fd that OPENS and then fails on
#     first use — invisible to a test that only opens.
#   * APPEND / TRUNCATE / SEEK, which are flags and offsets rather than
#     capabilities, and are where a mapping table gets silently transposed.
#     A whence table that swapped CUR and END still reads SOMETHING at every
#     position, which is why the slice seeks from both ends and tells.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-wasi.$$
mkdir -p "$work/native" "$work/sandbox"
trap 'rm -rf "$work"' EXIT

# The native run happens INSIDE its own directory, because the slice creates,
# renames and erases files by relative name — and the wasm run sees exactly one
# preopened directory. Anything else would compare a program with a filesystem
# against one without.
"$root/compiler/pascal26" -Fulib/rtl/platform/posix \
    "$here/wasi_slice.pas" "$work/native/prog" >/dev/null
(cd "$work/native" && ./prog) > "$work/native.txt"
rm -f "$work/native/prog"

"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/wasi_slice.pas" "$work/w.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/w.wasm"

if grep -qE '^    (Dec3|main\$[0-9])' "$work/cov.txt"; then
  echo "FAIL a routine of this slice was emitted as unreachable:"
  grep -E '^    (Dec3|main\$[0-9])' "$work/cov.txt"
  exit 1
fi
echo "ok  every routine in the slice lowered"

node --no-warnings "$here/wasihost.js" "$work/w.wasm" "$work/sandbox" \
    > "$work/wasm.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output, so the comparison below"; echo "     had nothing to compare and would have passed on two empty files"; exit 1; }
if diff -u "$work/native.txt" "$work/wasm.txt"; then
  echo "ok  wasm matches the native build ($(wc -l < "$work/native.txt") lines):"
  echo "..  write / read back / truncate / append; the PAL directly for a"
  echo "..  byte-exact write, a seek from both ends and a tell; a missing file"
  echo "..  and a path under no grant; rename, erase, mkdir/rmdir; \$sp balanced"
else
  echo "FAIL wasm diverges from native"; exit 1
fi

# The slice erases everything it made. A leftover file means an Erase or an
# unlink silently did nothing — which the diff cannot see, because both builds
# print the same success code either way.
if [ -n "$(ls -A "$work/sandbox")" ]; then
  echo "FAIL the sandbox is not empty after the slice cleaned up — an unlink"
  echo "     reported success without removing anything:"
  ls -A "$work/sandbox"
  exit 1
fi
echo "ok  the sandbox is empty afterwards — every unlink actually unlinked"

# --- the platform IDENTITY, which must DIFFER --------------------------------
# Deliberately not in the diffed slice: WASI is not posix and must not answer
# that it is. A backend that reported PAL_PLATFORM_POSIX would pass every other
# assertion here while telling a caller it has fork, users and sockets.
cat > "$work/id.pas" <<'EOF'
program Id;
uses platform;
begin
  writeln(PalPlatform, ' ', PalHasFiles, ' ', PalHasSockets, ' ', PalHasThreads);
end.
EOF
"$root/compiler/pascal26" -Fulib/rtl/platform/posix "$work/id.pas" \
    "$work/idn" >/dev/null
"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$work/id.pas" "$work/id.wasm" >/dev/null 2>&1
nat=$("$work/idn")
was=$(node --no-warnings "$here/wasihost.js" "$work/id.wasm" "$work/sandbox")
if [ "$nat" != "1 TRUE TRUE TRUE" ]; then
  echo "FAIL the native build no longer reports itself as POSIX with files,"
  echo "     sockets and threads — got: $nat"
  exit 1
fi
if [ "$was" != "3 TRUE FALSE FALSE" ]; then
  echo "FAIL wasm32 must report PAL_PLATFORM_WASI (3), files yes (a directory"
  echo "     was preopened), sockets no and threads no — got: $was"
  exit 1
fi
echo "ok  the two builds disagree about the platform, correctly:"
echo "..  posix [$nat] vs wasi [$was]"

# HasFiles is a question about the GRANT, not about the backend: WASI with no
# preopened directory can open nothing, and a program asking this is asking
# whether it may try. Answering TRUE unconditionally would be the easy version
# and would be wrong in the one case the question exists for.
nogrant=$(node --no-warnings "$here/wasihost.js" "$work/id.wasm" "")
if [ "$nogrant" != "3 FALSE FALSE FALSE" ]; then
  echo "FAIL with no preopened directory PalHasFiles must be FALSE — got:"
  echo "     $nogrant"
  exit 1
fi
echo "ok  with no directory granted, the same module reports no files —"
echo "..  the capability model, not a compile-time constant"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/wasi_slice.pas" \
   "$work" w -Fulib/rtl/platform/wasi

echo "PASS check_wasi"
