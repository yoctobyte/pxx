#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (ESP32-C3) build: compile main.pas to a relocatable object,
# wrap it in an archive, then drive the normal IDF build.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh            build only
#          ./build.sh qemu       build, then boot under Espressif QEMU
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="$REPO_ROOT/compiler/pascal26"

# See net-c3/build.sh: --platform=esp (IDF heap) and --no-signals (no
# rt_sigaction in the prologue) are both required, and each is silent when
# missing — the app panics at "Calling app_main()" and boot-loops.
"$PXX" --target=riscv32 --platform=esp --no-signals main/main.pas main/main.o
ar rcs main/libpxx_app.a main/main.o

idf.py set-target esp32c3
idf.py build

grep -q " app_main" build/pxx_hello_c3.map && echo "app_main present in image map"

if [ "${1:-}" = "qemu" ]; then
  idf.py qemu monitor
fi
