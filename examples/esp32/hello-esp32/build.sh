#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PXX="${PXX:-$("$ROOT/tools/pxx_stable.sh")}"  # the pin in a checkout, compiler/pxx-<arch> in a release

cd "$(dirname "$0")"

rm -f main/main.o main/libpxx_app.a
# The CHIP NAME, not --target=xtensa: the generic spelling answers the S3's
# memory map and instruction set, and this is an LX6. The chip name also
# implies the windowed ABI on the IDF platform.
"$PXX" --target=esp32 main/main.pas main/main.o
xtensa-esp32-elf-ar rcs main/libpxx_app.a main/main.o

idf.py set-target esp32
idf.py build

grep -q " app_main" build/pxx_hello_esp32.map && echo "app_main present in image map"
