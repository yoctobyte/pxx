#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (ESP32-C3): a static Python application. main/main.npy is
# compiled by pxx's NilPy frontend to a relocatable riscv32 object, wrapped in
# an archive, and linked by the normal IDF build. There is no interpreter on
# the chip.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh               build only
#          ./build.sh qemu-assert   build, boot under Espressif QEMU, and diff
#                                   the program's output against
#                                   main/main.expected (CPython's own output)
#
# Its OWN project, not tools/esp_run.sh's hello-c3, for the same reason as
# fs-c3: it needs its own partition table. The NilPy runtime is ~3 MB of code
# without --dce and the stock 1 MB factory app partition cannot hold it, so
# this project is 4 MB of flash with one large app (partitions.csv). Code is
# FLASH on this profile; SRAM is data+bss, ~175 KB here.
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$REPO_ROOT/stable_linux_amd64/default/pinned}"

# --no-signals as well as --platform=esp: the signal runtime's rt_sigaction
# install is an ecall in app_main's prologue, fatal under FreeRTOS.
"$PXX" --target=riscv32 --platform=esp --no-signals -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" main/main.npy main/main.o
ar rcs main/libpxx_app.a main/main.o

# `set-target` WIPES build/ and reconfigures -- only when not configured yet.
if ! grep -q '^CONFIG_IDF_TARGET="esp32c3"' sdkconfig 2>/dev/null; then
  idf.py set-target esp32c3
fi
# ninja does not see inside the prebuilt archive; drop the image to force a
# relink, or a previous program's binary would boot instead.
rm -f build/*.elf build/*.bin
idf.py build

grep -q " app_main" build/pxx_nilpy_c3.map && echo "app_main present in image map"

# Non-interactive acceptance, the fs-c3 recipe: serial to a FILE, let the
# timeout fire, assert on what was captured.
#
# WHAT A PASS WITNESSES: the program's stdout on an emulated ESP32-C3, under
# FreeRTOS, is byte-identical to CPython's. WHAT IT DOES NOT: silicon.
if [ "${1:-}" = "qemu-assert" ]; then
  QEMU_BIN="${QEMU_BIN:-$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1)}"
  if [ -z "$QEMU_BIN" ] || [ ! -x "$QEMU_BIN" ]; then
    echo "SKIP qemu-assert -- no Espressif qemu-system-riscv32 under ~/.espressif/tools"
    exit 77
  fi
  ( cd build && esptool --chip esp32c3 merge-bin --pad-to-size 4MB \
      -o qemu_flash.bin @flash_args >/dev/null )
  # DEFAULT efuse, not a blank one: an all-zero block reports chip revision
  # v0.0, the bootloader rejects the image and reboots forever (fs-c3/build.sh).
  python3 - "$PWD/build/qemu_efuse.bin" <<'PYEFUSE'
import sys, os
sys.path.insert(0, os.path.join(os.environ['IDF_PATH'], 'tools'))
from idf_py_actions.qemu_ext import QEMU_TARGETS
open(sys.argv[1], 'wb').write(QEMU_TARGETS['esp32c3'].default_efuse)
PYEFUSE
  ser="$(mktemp)"
  trap 'rm -f "$ser"' EXIT
  timeout 40 "$QEMU_BIN" -nographic -machine esp32c3 \
    -drive file=build/qemu_flash.bin,if=mtd,format=raw \
    -drive file=build/qemu_efuse.bin,if=none,format=raw,id=efuse \
    -global driver=nvram.esp32c3.efuse,property=drive,value=efuse \
    -serial "file:$ser" </dev/null >/dev/null 2>&1 || true
  # The program's output is everything after IDF's "Calling app_main()" line,
  # minus IDF's own log lines ("I (123) tag: ...").
  got="$(tr -d '\r' < "$ser" | awk 'f && !/^[IWE] \([0-9]+\) / {print} /Calling app_main\(\)/{f=1}')"
  want="$(cat main/main.expected)"
  if [ "$got" = "$want" ]; then
    echo "OK   nilpy-c3 -- a static Python application runs on the ESP32-C3, output == CPython"
  else
    echo "FAIL nilpy-c3 -- output differs from CPython (main/main.expected)"
    echo "want:"; printf '%s\n' "$want" | sed 's/^/    /'
    echo "got:";  printf '%s\n' "$got"  | sed 's/^/    /'
    echo "serial tail:"; tr -d '\r' < "$ser" | tail -25 | sed 's/^/    /'
    exit 1
  fi
fi
