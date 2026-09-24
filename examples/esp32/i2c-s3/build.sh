#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (ESP32-S3): the I2C bus test. main/main.pas uses espi2c; it
# is compiled to a relocatable object, wrapped in an archive, and linked by
# the normal IDF build.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh            build only
# On a board, from the repo root:
#   tools/esp_flash.sh --project examples/esp32/i2c-s3 --port /dev/ttyACM0
# There is no qemu mode: Espressif's qemu does not model the I2C controllers.
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
grep -q " app_main" build/pxx_i2c_s3.map && echo "app_main present in image map"
