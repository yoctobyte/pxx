#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PXX="${PXX:-$("$ROOT/tools/pxx_stable.sh")}"  # the pin in a checkout, compiler/pxx-<arch> in a release

cd "$(dirname "$0")"

rm -f main/main.o main/libpxx_app.a
# The chip name, not --target=xtensa: that one means the S3, whose atomic
# instruction (S32C1I) the S2 does not have. esp32s2 implies windowed on IDF.
"$PXX" --target=esp32s2 main/main.pas main/main.o
xtensa-esp32s2-elf-ar rcs main/libpxx_app.a main/main.o

idf.py set-target esp32s2
idf.py build

grep -q " app_main" build/pxx_hello_s2.map && echo "app_main present in image map"
