#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (ESP32-S3): the NVS test. main/main.pas uses espnvs and checks
# that settings survive a software reboot and a hardware reset. It is compiled
# to a relocatable object, wrapped in an archive, and linked by the IDF build.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh            build only
# On a board, from the repo root:
#   tools/esp_flash.sh --project examples/esp32/nvs-s3 --port /dev/ttyACM0
# Board only: the hardware-reset phase needs a real reset line. esp_flash.sh
# reports "the board rebooted during the capture" for this test; the two
# esp_restart calls are the test, so read the rows, not that verdict. Then
# reset the board once (the reset button, or replug) for phase 3.
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
grep -q " app_main" build/pxx_nvs_s3.map && echo "app_main present in image map"
