#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# Usage:   ./build.sh            build only
#          ./build.sh qemu       boot main.pas headless under Espressif QEMU
#                                (tools/esp_run.sh), printing its output
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PXX="${PXX:-$("$ROOT/tools/pxx_stable.sh")}"  # the pin in a checkout, compiler/pxx-<arch> in a release

cd "$(dirname "$0")"

# Arguments are checked BEFORE the build: an unknown one used to be ignored
# silently (the build ran and exited 0, so `./build.sh qemu` on hello-s3
# looked like a pass that never booted anything).
MODE="${1:-}"
case "$MODE" in
  "")          ;;
  qemu)        # headless: tools/esp_run.sh builds its own staged copy, boots it
               # under Espressif QEMU and prints what the program wrote
               ESP_RUN_PXX="$PXX" exec "$ROOT/tools/esp_run.sh" --chip esp32s3 main/main.pas ;;
  *) echo "usage: $0 [qemu]   (got: $MODE)" >&2; exit 2 ;;
esac

rm -f main/main.o main/libpxx_app.a
"$PXX" --target=xtensa --xtensa-abi=windowed main/main.pas main/main.o
xtensa-esp32s3-elf-ar rcs main/libpxx_app.a main/main.o

idf.py set-target esp32s3
idf.py build

grep -q " app_main" build/pxx_hello_s3.map && echo "app_main present in image map"
