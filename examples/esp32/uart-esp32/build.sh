#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (classic ESP32, Xtensa LX6): the UART1 test. main/main.pas uses
# espuart and checks it with no wire: the UART's internal loopback, then TX and
# RX on one pad. It is compiled to a relocatable object, wrapped in an archive,
# and linked by the IDF build. Same source as examples/esp32/uart-s3 except for
# the program name.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh            build only
# On a board, from the repo root:
#   tools/esp_flash.sh --project examples/esp32/uart-esp32 --port /dev/ttyUSB0
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$("$REPO_ROOT/tools/pxx_stable.sh")}"  # the pin in a checkout, compiler/pxx-<arch> in a release
# --target=esp32, THE CHIP NAME, not `--target=xtensa --xtensa-abi=windowed` as
# uart-s3 spells it: the generic xtensa spelling answers the S3's memory map and
# this is an LX6, and the chip name implies the windowed ABI on the IDF
# platform. Same reasoning as hello-esp32 and timer-esp32.
"$PXX" --target=esp32 --platform=esp --no-signals \
  -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" \
  main/main.pas main/main.o
xtensa-esp32-elf-ar rcs main/libpxx_app.a main/main.o
if ! grep -q '^CONFIG_IDF_TARGET="esp32"' sdkconfig 2>/dev/null; then
  idf.py set-target esp32
fi
idf.py build
grep -q " app_main" build/pxx_uart_esp32.map && echo "app_main present in image map"
