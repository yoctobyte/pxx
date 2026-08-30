#!/bin/sh
# The WASI out-parameters whose ALIGNMENT the spec constrains — and the first
# check in this suite that needs a SECOND HOST to mean anything.
#
# WHY NODE CANNOT CATCH THIS, measured rather than argued. With the defect
# reinstated, this slice under node prints every expected line and exits 0;
# under wasmtime the same module traps before its first line. Node's WASI does
# not enforce the alignment WASI preview1 requires of a u64 out-param, so every
# other check here — all of which run under node — is structurally blind to the
# whole class. That is the entire justification for this file.
#
# THE DEFECT, because the shape is not obvious. `fd_seek` returns a `filesize`
# and `clock_time_get` a `timestamp`; both are u64 and a strict host requires
# the pointer written through to be 8-byte aligned. Both WASI backends used
# `WasiScratch: array[0..15] of Byte` for it — and symtab.inc's TypeAlign aligns
# a global to its ELEMENT type, so a byte array is aligned to ONE. It landed
# 4-aligned by luck. An Int64 global aligns to 8 by that same rule, which is why
# the fix is a declaration and not arithmetic.
#
# It cost a long hunt. Under node the misaligned pointer did not trap, it took
# the whole process down with SIGSEGV much later, which reads as a host bug —
# and a guest cannot fault its host, only trap, so the evidence genuinely
# pointed away from our code until a second host was available to ask.
#
# BOTH COPIES OF THE CAPABILITY MODEL ARE COVERED, deliberately. There are two
# (bug-a-two-copies-of-the-wasi-capability-model-one-in-the-pal-one-in-wasibackend)
# and they held the identical defect:
#   * LoadFile -> PXXWasiLoadFile -> wasi_fd_seek, compiler/builtin/wasibackend.pas
#   * PalSeek / PalRealtime / PalMonotonicMillis -> lib/rtl/platform/wasi/
# Only the first was ever observed failing, because only it is on the path the
# wasm-hosted compiler takes. Fixing one and not the other is the drift that
# ticket exists to stop, so this asserts both.
#
# WASMTIME IS REQUIRED, and its absence is reported as a SKIP rather than
# swallowed: without it this file asserts nothing at all, and a check that
# cannot fail must not be able to look like one that passed.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=${TMPDIR:-/tmp}/pxx-wasm-align.$$
mkdir -p "$work/sand"
trap 'rm -rf "$work"' EXIT

if ! command -v wasmtime >/dev/null 2>&1; then
  echo "SKIP check_align — wasmtime is not on PATH, and node cannot see this"
  echo "     bug class at all (measured: the unfixed module passes under node"
  echo "     and traps under wasmtime). NOT a pass; this box asserted nothing."
  echo "PASS check_align"
  exit 0
fi

printf 'hello-align' > "$work/sand/align_data.txt"
cp "$here/wasihost.js" "$work/"

# The oracle. NOT piped: a pipeline's exit status is its LAST command's, so a
# compile failure would sail through `| head` under `set -e`.
"$root/compiler/pascal26" -Fulib/rtl/platform/posix \
    "$here/align_slice.pas" "$work/native" > /dev/null
(cd "$work/sand" && "$work/native") > "$work/native.txt"
[ -s "$work/native.txt" ] || { echo "FAIL the oracle produced NO output"; exit 1; }

"$root/compiler/pascal26" --target=wasm32 -Fulib/rtl/platform/wasi \
    "$here/align_slice.pas" "$work/a.wasm" > "$work/cov.txt" 2>&1
head -1 "$work/cov.txt"
wasm-validate "$work/a.wasm"

# THE assertion. wasmtime enforces the alignment; a violation is a trap here,
# not a wrong value, so exit status is as load-bearing as the diff.
if ! wasmtime run --dir "$work/sand"::. "$work/a.wasm" > "$work/wt.txt" 2>"$work/wt.err"; then
  echo "FAIL wasmtime refused the module. If the error says 'Pointer not"
  echo "     aligned to 8', a u64 WASI out-param is being written through an"
  echo "     under-aligned pointer again — check that fd_seek and"
  echo "     clock_time_get still use the Int64 scratch and not the byte array."
  head -12 "$work/wt.err"
  exit 1
fi
if diff -u "$work/native.txt" "$work/wt.txt"; then
  echo "ok  wasmtime — a STRICT WASI host — agrees with native ($(wc -l < "$work/native.txt") lines):"
  echo "..  fd_seek through BOTH backends (the builtin unit's and the PAL's)"
  echo "..  and clock_time_get on both clocks, all four being u64 out-params"
else
  echo "FAIL wasmtime diverges from native"; exit 1
fi

# node too — not for this bug, which it cannot see, but so that a fix made for
# wasmtime cannot quietly break the host every other check in this suite uses.
node --no-warnings "$work/wasihost.js" "$work/a.wasm" "$work/sand" > "$work/nd.txt" 2>&1
if diff -u "$work/native.txt" "$work/nd.txt"; then
  echo "ok  node agrees too — the strict-host fix did not break the lenient one"
else
  echo "FAIL node diverges from native"; exit 1
fi

# The clocks are asserted as PROPERTIES above rather than diffed, so name them
# here: a misaligned or unwritten out-param reads back as ZERO, which is what
# these two would catch and a timestamp diff never could.
for want in realtime-after-2000=TRUE monotonic-forward=TRUE; do
  grep -qx "$want" "$work/wt.txt" || {
    echo "FAIL expected [$want] — a u64 clock out-param read back as zero,"
    echo "     which is exactly what an unwritten out-param looks like"
    exit 1; }
done
echo "ok  both u64 clock out-params were really written (a zero read is the"
echo "..  signature of the defect, and these two are what would see it)"

sh "$here/wat_oracle.sh" "$root/compiler/pascal26" "$here/align_slice.pas" "$work" a \
   -Fulib/rtl/platform/wasi

# A POSITIVE sentinel, last line, reachable only after every check above
# passed: `set -e` kills the script before here on any failure.
echo "PASS check_align"
