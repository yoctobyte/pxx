#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (ESP32-S3, Xtensa/windowed) esptimer demo: the same source as
# examples/esp32/timer-c3, compiled for the OTHER ISA. The point is that the
# event surface (TimerInit / OnElapsed / TimerStartPeriodicMs) and the callback
# taken with @ are ABI-portable: nothing in main.pas changes between chips.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh            build only
#          ./build.sh qemu       build, then boot under Espressif QEMU
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$REPO_ROOT/stable_linux_amd64/default/pinned}"

# --no-signals as well as --platform=esp: the signal runtime's rt_sigaction
# install is an ecall in app_main's prologue, fatal under FreeRTOS.
"$PXX" --target=xtensa --xtensa-abi=windowed --platform=esp --no-signals \
  -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" \
  main/main.pas main/main.o
xtensa-esp32s3-elf-ar rcs main/libpxx_app.a main/main.o

idf.py set-target esp32s3
idf.py build

grep -q " app_main" build/pxx_timer_s3.map && echo "app_main present in image map"

if [ "${1:-}" = "qemu" ]; then
  idf.py qemu monitor
fi
