#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (ESP32-C3) build: compile main.pas to a relocatable object,
# wrap it in an archive, then drive the normal IDF build.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh            build only
#          ./build.sh qemu       boot main.pas headless under Espressif QEMU
#                                (tools/esp_run.sh), printing its output
#          ./build.sh qemu-monitor  build, then the interactive `idf.py qemu monitor`
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$("$REPO_ROOT/tools/pxx_stable.sh")}"  # the pin in a checkout, compiler/pxx-<arch> in a release
ROOT="$REPO_ROOT"

# Arguments are checked BEFORE the build: an unknown one used to be ignored
# silently (the build ran and exited 0, so `./build.sh qemu` on hello-s3
# looked like a pass that never booted anything).
MODE="${1:-}"
case "$MODE" in
  "")          ;;
  qemu)        # headless: tools/esp_run.sh builds its own staged copy, boots it
               # under Espressif QEMU and prints what the program wrote
               ESP_RUN_PXX="$PXX" exec "$ROOT/tools/esp_run.sh" --chip esp32c3 main/main.pas ;;
  qemu-monitor) ;;  # the interactive idf.py monitor, after the build below
  *) echo "usage: $0 [qemu|qemu-monitor]   (got: $MODE)" >&2; exit 2 ;;
esac

# See net-c3/build.sh: --platform=esp (IDF heap) and --no-signals (no
# rt_sigaction in the prologue) are both required, and each is silent when
# missing — the app panics at "Calling app_main()" and boot-loops.
"$PXX" --target=riscv32 --platform=esp --no-signals main/main.pas main/main.o
ar rcs main/libpxx_app.a main/main.o

idf.py set-target esp32c3
idf.py build

grep -q " app_main" build/pxx_hello_c3.map && echo "app_main present in image map"

if [ "$MODE" = "qemu-monitor" ]; then
  idf.py qemu monitor
fi
