#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PXX="$ROOT/compiler/pascal26"

cd "$(dirname "$0")"

rm -f main/main.o main/libpxx_app.a
"$PXX" --target=xtensa --xtensa-abi=windowed main/main.pas main/main.o
xtensa-esp32s3-elf-ar rcs main/libpxx_app.a main/main.o

idf.py set-target esp32s3
idf.py build

grep -q " app_main" build/pxx_hello_s3.map && echo "app_main present in image map"
