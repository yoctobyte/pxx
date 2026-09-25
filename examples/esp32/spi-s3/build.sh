#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (ESP32-S3): the SPI master test. main/main.pas uses espspi; it
# is compiled to a relocatable object, wrapped in an archive, and linked by
# the normal IDF build.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh            build only
# On a board, from the repo root:
#   tools/esp_flash.sh --project examples/esp32/spi-s3 --port /dev/ttyACM0
# Under qemu:  ./build.sh qemu-assert
#   boots the image in Espressif's qemu and compares the first seven lines
#   (open, the two refusals, both devices, the clock readback) with
#   main/qemu.expected. That is the unit's structs going through the real
#   driver. qemu stops there: its SPI2 model never completes a transaction, so
#   the first transfer spins until the timeout (measured 2026-09-25, IDF
#   v6.0.1's qemu). The transfer rows need a board.
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$REPO_ROOT/stable_linux_amd64/default/pinned}"
"$PXX" --target=xtensa --xtensa-abi=windowed --platform=esp --no-signals \
  -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" \
  main/main.pas main/main.o
xtensa-esp32s3-elf-ar rcs main/libpxx_app.a main/main.o
if ! grep -q '^CONFIG_IDF_TARGET="esp32s3"' sdkconfig 2>/dev/null; then
  idf.py set-target esp32s3
fi
idf.py build
grep -q " app_main" build/pxx_spi_s3.map && echo "app_main present in image map"

if [ "${1:-}" = "qemu-assert" ]; then
  QEMU_BIN="${QEMU_BIN:-$(ls "$HOME"/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1)}"
  if [ -z "$QEMU_BIN" ] || [ ! -x "$QEMU_BIN" ]; then
    echo "SKIP -- no Espressif qemu for esp32s3 under ~/.espressif/tools"
    exit 77
  fi
  ( cd build && esptool --chip esp32s3 merge-bin --pad-to-size 4MB \
      -o qemu_flash.bin @flash_args >/dev/null )
  ser="$(mktemp)"
  trap 'rm -f "$ser"' EXIT
  timeout 20 "$QEMU_BIN" -nographic -machine esp32s3 \
    -drive file=build/qemu_flash.bin,if=mtd,format=raw \
    -serial "file:$ser" </dev/null >/dev/null 2>&1 || true
  got="$(tr -d '\r' < "$ser" | sed -n '/^SPI-MASTER SPI2/,$p' | head -7)"
  boots="$(grep -c 'ESP-ROM' "$ser" || true)"
  if [ "$got" = "$(cat main/qemu.expected)" ] && [ "$boots" = 1 ]; then
    echo "OK   spi-s3 -- bus and devices open under qemu, output == main/qemu.expected, one boot"
  else
    echo "FAIL spi-s3 -- output differs from main/qemu.expected, or the chip rebooted (boots=$boots)"
    echo "got:"; printf '%s\n' "$got" | sed 's/^/    /'
    echo "serial tail:"; tr -d '\r' < "$ser" | tail -20 | sed 's/^/    /'
    exit 1
  fi
fi
