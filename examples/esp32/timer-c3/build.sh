#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (ESP32-C3) esptimer demo: compile main.pas (uses esptimer) to a
# relocatable object, wrap it in an archive, then drive the normal IDF build.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh            build only
#          ./build.sh qemu       build, then boot under Espressif QEMU
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$REPO_ROOT/stable_linux_amd64/default/pinned}"

"$PXX" --target=riscv32 --platform=esp -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" main/main.pas main/main.o
ar rcs main/libpxx_app.a main/main.o

idf.py set-target esp32c3
idf.py build

grep -q " app_main" build/pxx_timer_c3.map && echo "app_main present in image map"

if [ "${1:-}" = "qemu" ]; then
  idf.py qemu monitor
fi
