#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# Build the RGB-fade demo. Prereqs: . ~/esp/esp-idf/export.sh
# On silicon, from the repo root:
#   tools/esp_flash.sh --project examples/esp32/rgb-s3 --no-verify
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$("$REPO_ROOT/tools/pxx_stable.sh")}"  # the pin in a checkout, compiler/pxx-<arch> in a release

rm -f main/main.o main/libpxx_app.a
"$PXX" --target=xtensa --xtensa-abi=windowed --platform=esp main/main.pas main/main.o
xtensa-esp32s3-elf-ar rcs main/libpxx_app.a main/main.o

# The archive is a dependency of the .elf, so ninja relinks on its own when
# it changes, without regenerating sections.ld (see main/CMakeLists.txt).
if [ -f build/build.ninja ]; then
  ninja -C build
else
  idf.py set-target esp32s3
  idf.py build
fi
