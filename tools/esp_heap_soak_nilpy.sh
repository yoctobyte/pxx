#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Heap soak of an examples/esp32 NIL PYTHON program under the Espressif QEMU --
# the NilPy counterpart of tools/esp_heap_soak.sh, which rewrites a Pascal main
# and cannot take a Python one.
#
#   tools/esp_heap_soak_nilpy.sh [--control] [--passes N] [--settle S] <example-dir-name>
#
# The example is staged OUT OF TREE (symlinks dereferenced; the checkout stays
# byte-clean) and a footer is appended to its main.npy:
#   two warm-up passes, free heap, N passes, free heap, then
#   SOAK <example> <chip> delta=<bytes> passes=<N> bpp=<bytes per pass>
# and, last, SOAK-COMPLETE. Grep for that token; the wrapper's exit status is
# not the verdict. The heap is IDF's esp_get_free_heap_size (espsys.free_heap):
# on the IDF profile pxx's allocator IS newlib/picolibc malloc, so it sees every
# NilPy object.
#
# THE PASS BODY. tools/esp_soak_nilpy/<example>.npy, when it exists, defines
# `def soak_body():`. If its first line is `# SOAK-REPLACES-MAIN` it REPLACES
# main.npy (for a program whose own top level needs the radio, which QEMU does
# not have, or never returns); otherwise it is appended after the program. With
# no such file the body is the program's own `main()`. The program's top level
# runs once before the footer either way, so it is a warm-up, not a pass.
#
# --control adds a deliberate 64-byte GetMem with no free to every pass, from a
# 12-line Pascal unit staged beside main.npy (soakctl.pas): the instrument must
# then read 64 + the allocator's per-block header per pass, in the same program
# and at the same scale as the measurement. tools/esp_heap_soak.sh measured that
# header as 12 on both chips, 2026-09-25.
#
# --settle S idles S seconds after the passes and reads the heap again:
#   SOAK-SETTLED delta=<bytes still gone>
# which separates a leak from memory that is only HELD for a while. lwIP keeps
# every closed TCP connection in TIME_WAIT for 2*TCP_MSL (IDF: 120 s), so a
# program that opens connections shows a per-pass cost that returns once they
# expire; a leak does not return.
#
# Built with the example's own build.sh (so its flags, partition table and
# sdkconfig), with the PINNED compiler unless SOAK_PXX says otherwise.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL=0; PASSES="${SOAK_N:-10}"; SETTLE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --control) CONTROL=1; shift ;;
    --passes) PASSES="$2"; shift 2 ;;
    --settle) SETTLE="$2"; shift 2 ;;
    *) break ;;
  esac
done
EX="${1:?usage: esp_heap_soak_nilpy.sh [--control] [--passes N] <example>}"
SRC="$REPO_ROOT/examples/esp32/$EX"
[ -f "$SRC/main/main.npy" ] || { echo "soak: $EX has no main/main.npy" >&2; exit 2; }
PXX="${SOAK_PXX:-$("$REPO_ROOT/tools/pxx_stable.sh")}"
TIMEOUT="${SOAK_TIMEOUT:-240}"
ESP_IDF_DIR="${ESP_IDF_DIR:-$HOME/esp/esp-idf}"
BODY="${SOAK_BODY:-$REPO_ROOT/tools/esp_soak_nilpy/$EX.npy}"

W="$(mktemp -d "${TMPDIR:-/tmp}/esp-soak-nilpy.XXXXXX")"
QPID=""
cleanup() {
  [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
  if [ -n "${SOAK_KEEP:-}" ]; then echo "soak: stage kept at $W" >&2; else rm -rf "$W"; fi
}
trap cleanup EXIT

mkdir -p "$W/$EX"
tar -C "$SRC" -h --exclude=build --exclude=sdkconfig --exclude='*.o' --exclude='*.a' -cf - . \
  | tar -C "$W/$EX" -xf -
cd "$W/$EX"
case "$EX" in *-c3) CHIP=esp32c3 ;; *-s3) CHIP=esp32s3 ;; *) echo "soak: $EX is not -c3/-s3" >&2; exit 2 ;; esac

cat > main/soakctl.pas <<'PAS'
{ SPDX-License-Identifier: MPL-2.0 }
unit soakctl;
{ tools/esp_heap_soak_nilpy.sh --control: a known leak per pass. }
interface
procedure leak64;
implementation
procedure leak64;
var p: Pointer;
begin
  GetMem(p, 64);
end;
end.
PAS

if [ -f "$BODY" ] && head -1 "$BODY" | grep -q 'SOAK-REPLACES-MAIN'; then
  cp "$BODY" main/main.npy
elif [ -f "$BODY" ]; then
  { printf '\n'; cat "$BODY"; } >> main/main.npy
else
  printf '\n\ndef soak_body():\n    main()\n' >> main/main.npy
fi
{
  printf '\n\n# ---- appended by tools/esp_heap_soak_nilpy.sh ----\n'
  printf "import 'espsys.pas' as _soak_board\n"
  [ "$CONTROL" = 1 ] && printf "import 'soakctl.pas' as _soak_ctl\n"
  printf '\n\ndef _soak_pass():\n    soak_body()\n'
  [ "$CONTROL" = 1 ] && printf '    _soak_ctl.leak64()\n'
  printf '\n\n_soak_pass()\n_soak_pass()\n'
  printf '_soak_h0 = _soak_board.free_heap()\n'
  printf 'for _soak_i in range(%d):\n    _soak_pass()\n' "$PASSES"
  printf '_soak_h1 = _soak_board.free_heap()\n'
  printf '_soak_d = _soak_h0 - _soak_h1\n'
  printf 'print("SOAK-RESULT delta=" + str(_soak_d) + " passes=%d bpp=" + str(_soak_d // %d))\n' "$PASSES" "$PASSES"
  if [ "$SETTLE" != 0 ]; then
    printf 'import time as _soak_time\n_soak_time.sleep_ms(%d)\n' "$((SETTLE * 1000))"
    printf 'print("SOAK-SETTLED delta=" + str(_soak_h0 - _soak_board.free_heap()) + " after=%ds")\n' "$SETTLE"
  fi
  printf 'print("SOAK-COMPLETE")\n'
} >> main/main.npy

sed -i -e "s|^REPO_ROOT=.*|REPO_ROOT=\"$REPO_ROOT\"|" build.sh
# a project with its own IDF components (pxx_esp, pxx_fs) names them relative to
# the checkout, which the stage is not in
sed -i -e "s|\${CMAKE_CURRENT_LIST_DIR}/\.\./\.\./\.\.|$REPO_ROOT|g" CMakeLists.txt
. "$ESP_IDF_DIR/export.sh" >/dev/null 2>&1
if ! PXX="$PXX" PXX_EXTRA_FLAGS="-Fu$W/$EX/main ${PXX_EXTRA_FLAGS:-}" bash build.sh >"$W/build.log" 2>&1; then
  echo "SOAK $EX $CHIP BUILD-FAIL"; grep -a -m3 'error' "$W/build.log" | sed 's/^/  | /'
  tail -5 "$W/build.log" | sed 's/^/  | /'
  echo "SOAK-COMPLETE"; exit 1
fi

case "$CHIP" in
  esp32s3) QEMU="$(ls "$HOME"/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa | head -1)" ;;
  *)       QEMU="$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 | head -1)" ;;
esac
( cd build && python -m esptool --chip "$CHIP" merge-bin -o "$W/flash.bin" @flash_args --fill-flash-size 4MB >/dev/null 2>&1 )
"$QEMU" -M "$CHIP" -drive file="$W/flash.bin",if=mtd,format=raw -nographic -serial mon:stdio -monitor none \
  >"$W/serial.log" 2>&1 &
QPID=$!
t=0
while [ $t -lt "$TIMEOUT" ] && ! grep -qa 'SOAK-COMPLETE' "$W/serial.log"; do sleep 1; t=$((t + 1)); done
kill "$QPID" 2>/dev/null || true; QPID=""
tag="$EX $CHIP"; [ "$CONTROL" = 1 ] && tag="$tag control"
r="$(tr -d '\r' < "$W/serial.log" | grep -a 'SOAK-RESULT' | head -1 || true)"
if [ -n "$r" ]; then
  echo "SOAK $tag ${r#SOAK-RESULT }"
  st="$(tr -d '\r' < "$W/serial.log" | grep -a 'SOAK-SETTLED' | head -1 || true)"
  [ -n "$st" ] && echo "SOAK $tag settled ${st#SOAK-SETTLED }"
else
  echo "SOAK $tag NO-RESULT after ${t}s; last serial lines:"
  tr -d '\r' < "$W/serial.log" | tail -8 | sed 's/^/  | /'
fi
echo "SOAK-COMPLETE"
