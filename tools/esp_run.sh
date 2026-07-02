#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Boot a PXX program on an ESP32 chip under Espressif QEMU and print what
# app_main wrote to the ROM console, with the IDF boot banner stripped.
#
#   tools/esp_run.sh [--chip esp32s3|esp32c3] <prog.pas>
#
# Default chip is esp32s3 (Xtensa, the primary hardware target). The program is
# compiled to a relocatable object for the chip's ISA, dropped into the
# matching examples/esp32 IDF project as the app_main provider, linked by the
# normal IDF build, merged to a flash image, and booted under the Espressif
# qemu fork. Stdout is exactly the bytes the Pascal program emitted (serial
# CRLF normalized to LF), so it can be diffed against the program's x86-64 run
# (the oracle) for output-equality validation.
#
# Per chip:
#   esp32s3 -> --target=xtensa --xtensa-abi=windowed, project hello-s3,
#              qemu-system-xtensa  -M esp32s3
#   esp32c3 -> --target=riscv32,                       project hello-c3,
#              qemu-system-riscv32 -M esp32c3
#
# Prereqs (heavy, not part of `make test`):
#   - ESP-IDF checkout that exports idf.py + toolchains + esptool
#     (default ~/esp/esp-idf; override with ESP_IDF_DIR)
#   - Espressif qemu forks under ~/.espressif/tools/qemu-{xtensa,riscv32}
set -euo pipefail

CHIP=esp32s3
if [ "${1:-}" = "--chip" ]; then CHIP="$2"; shift 2; fi
PAS="${1:?usage: tools/esp_run.sh [--chip esp32s3|esp32c3] <prog.pas>}"
PAS="$(cd "$(dirname "$PAS")" && pwd)/$(basename "$PAS")"   # absolute; survives cd
TIMEOUT="${ESP_RUN_TIMEOUT:-15}"
ESP_IDF_DIR="${ESP_IDF_DIR:-$HOME/esp/esp-idf}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PXX="$REPO_ROOT/compiler/pascal26"

case "$CHIP" in
  esp32s3)
    PROJ="$REPO_ROOT/examples/esp32/hello-s3"
    PXXFLAGS="--target=xtensa --xtensa-abi=windowed"
    QEMU="$(ls "$HOME"/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1)" ;;
  esp32c3)
    PROJ="$REPO_ROOT/examples/esp32/hello-c3"
    PXXFLAGS="--target=riscv32"
    QEMU="$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1)" ;;
  *) echo "esp_run: unknown chip '$CHIP' (esp32s3|esp32c3)" >&2; exit 2 ;;
esac

[ -x "$PXX" ]    || { echo "esp_run: compiler not built ($PXX)" >&2; exit 2; }
[ -n "$QEMU" ]   || { echo "esp_run: Espressif qemu for $CHIP not found" >&2; exit 2; }
[ -d "$PROJ" ]   || { echo "esp_run: IDF project $PROJ missing" >&2; exit 2; }
[ -f "$ESP_IDF_DIR/export.sh" ] || { echo "esp_run: ESP-IDF not at $ESP_IDF_DIR" >&2; exit 2; }

# shellcheck disable=SC1091
. "$ESP_IDF_DIR/export.sh" >/dev/null 2>&1

cd "$PROJ"
# shellcheck disable=SC2086
"$PXX" $PXXFLAGS ${ESP_PXXFLAGS:-} "$PAS" main/main.o >/dev/null
ar rcs main/libpxx_app.a main/main.o
# The Pascal code arrives via add_prebuilt_library (libpxx_app.a), which ninja
# does NOT track for content changes -- so force a relink by removing the app
# image, or a stale binary from a previous program would boot instead. Build
# errors (e.g. an undefined external) must abort, not silently run the old image.
if [ -f build/build.ninja ]; then
  rm -f build/*.elf build/*.bin
  ninja -C build >/dev/null || { echo "esp_run: build failed" >&2; exit 1; }
else
  idf.py set-target "$CHIP" >/dev/null && idf.py build >/dev/null || { echo "esp_run: build failed" >&2; exit 1; }
fi

cd build
python -m esptool --chip "$CHIP" merge-bin -o /tmp/esp_run_flash.bin \
  @flash_args --fill-flash-size 2MB >/dev/null 2>&1

SER="$(mktemp)"
timeout "$TIMEOUT" "$QEMU" -M "$CHIP" \
  -drive file=/tmp/esp_run_flash.bin,if=mtd,format=raw \
  -nographic -serial mon:stdio -monitor none >"$SER" 2>&1 || true

# Everything after the IDF "Calling app_main()" line is the program's output,
# minus the trailing qemu "terminating on signal" notice from the timeout kill.
# The esp serial console turns each '\n' into '\r\n'; strip the CR so the bytes
# match a plain-LF Linux oracle run.
awk 'f && !/qemu-system-[a-z0-9]*: terminating/ {print} /Calling app_main\(\)/{f=1}' "$SER" \
  | tr -d '\r'
rm -f "$SER"
