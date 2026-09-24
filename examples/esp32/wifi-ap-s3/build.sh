#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# Build the Wi-Fi AP + web page demo. Prereqs: . ~/esp/esp-idf/export.sh
# On silicon, from the repo root:
#   tools/esp_flash.sh --project examples/esp32/wifi-ap-s3 --no-verify
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$REPO_ROOT/stable_linux_amd64/default/pinned}"

"$PXX" --target=xtensa --xtensa-abi=windowed --platform=esp --no-signals \
  -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" \
  main/main.pas main/main.o
xtensa-esp32s3-elf-ar rcs main/libpxx_app.a main/main.o

# The archive is a dependency of the .elf, so ninja relinks on its own when
# it changes, without regenerating sections.ld (see main/CMakeLists.txt).
if [ -f build/build.ninja ]; then
  ninja -C build
else
  idf.py set-target esp32s3
  idf.py build
fi
