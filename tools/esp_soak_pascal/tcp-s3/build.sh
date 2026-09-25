#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# ESP32-S3 (xtensa, windowed) build of the TCP loopback soak body; staged and
# driven by tools/esp_heap_soak.sh (SOAK_SRC=tools/esp_soak_pascal).
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$("$REPO_ROOT/tools/pxx_stable.sh")}"
"$PXX" --target=xtensa --xtensa-abi=windowed --platform=esp --no-signals \
  -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" \
  main/main.pas main/main.o
xtensa-esp32s3-elf-ar rcs main/libpxx_app.a main/main.o
if ! grep -q '^CONFIG_IDF_TARGET="esp32s3"' sdkconfig 2>/dev/null; then
  idf.py set-target esp32s3
fi
idf.py build
