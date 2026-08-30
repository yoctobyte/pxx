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

# --no-signals as well as --platform=esp: the signal runtime's rt_sigaction
# install is an ecall in app_main's prologue, fatal under FreeRTOS.
"$PXX" --target=riscv32 --platform=esp --no-signals -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" main/main.pas main/main.o
ar rcs main/libpxx_app.a main/main.o

# `set-target` WIPES build/ and reconfigures, so running it unconditionally
# turns every invocation into a from-scratch ~988-target rebuild (minutes), and
# it also deletes the qemu flash/efuse images between a build and an assert.
# Only run it when the tree is not already configured for this chip.
if ! grep -q '^CONFIG_IDF_TARGET="esp32c3"' sdkconfig 2>/dev/null; then
  idf.py set-target esp32c3
fi
idf.py build

grep -q " app_main" build/pxx_timer_c3.map && echo "app_main present in image map"

if [ "${1:-}" = "qemu" ]; then
  idf.py qemu monitor
fi

# Non-interactive ACCEPTANCE. `qemu monitor` above is for a human at a console;
# it cannot assert, and piping it does not work either -- the app parks forever
# by design, so any `| tail` buffers until the timeout kills the pipeline and
# you capture nothing (measured 2026-08-30).
#
# So drive qemu directly with the serial line going to a FILE, let the timeout
# fire (rc 124 is the expected outcome, not a failure -- the app is meant to
# park), and assert on what was captured.
#
# WHAT A PASS HERE WITNESSES, precisely: a real esp_timer callback firing five
# times on the emulated C3, dispatched by FreeRTOS through the library's event
# surface, with TimerStop returning success. status is a bitmask the app builds
# itself -- 1 = start failed, 2 = fewer than 5 ticks arrived, 4 = stop failed --
# so `status=0` cannot be printed by a dead timer. This is the slice-1
# acceptance from feature-esp-peripheral-callback-api.
#
# WHAT IT DOES NOT WITNESS: silicon. QEMU is not an ESP32-C3; timing, the real
# peripheral, and anything analog are not exercised. It also says nothing about
# xtensa (S2/S3) -- that is timer-s3 and a different qemu binary.
if [ "${1:-}" = "qemu-assert" ]; then
  QEMU_BIN="${QEMU_BIN:-$HOME/.espressif/tools/qemu-riscv32/esp_develop_9.2.2_20250817/qemu/bin/qemu-system-riscv32}"
  if [ ! -x "$QEMU_BIN" ]; then
    echo "SKIP qemu-assert -- no Espressif qemu-system-riscv32 at $QEMU_BIN"
    echo "     (IDF installs it OFF PATH under ~/.espressif/tools/; a bare"
    echo "      \`command -v qemu-system-riscv32\` cannot see it and will"
    echo "      wrongly report the machine has no runner.)"
    exit 77
  fi
  # Build the 2MB flash image from the parts idf just built. This MUST be done
  # here rather than relying on a leftover: `idf.py set-target` above wipes
  # build/, so a qemu_flash.bin from an earlier run is gone by now. Leaving it
  # to chance is how the first cut of this script failed -- qemu booted with no
  # image and captured an empty serial log, which is indistinguishable from a
  # program that ran and printed nothing.
  # (idf.py qemu would also generate it, but it has no generate-only mode and
  # goes straight into an interactive session.)
  ( cd build && esptool --chip esp32c3 merge-bin --pad-to-size 2MB \
      -o qemu_flash.bin @flash_args >/dev/null )
  # The efuse image must carry the DEFAULTS for this chip, and a blank block is
  # NOT good enough: an all-zero efuse reports chip revision v0.0, the image
  # requires >= v0.3, and the bootloader then rejects it and reboots forever.
  # The serial log fills with boot attempts and contains not one line of app
  # output -- which looks identical to "the app printed nothing". Measured
  # 2026-08-30; it was the second bug in this script, after the missing flash
  # image, and both presented as the same empty capture.
  #
  # Take the blob from IDF's own table rather than pasting a copy here: it is
  # per-chip, upstream owns it, and a hardcoded copy would silently rot.
  python3 - "$PWD/build/qemu_efuse.bin" <<'PYEFUSE'
import sys, os
sys.path.insert(0, os.path.join(os.environ['IDF_PATH'], 'tools'))
from idf_py_actions.qemu_ext import QEMU_TARGETS
open(sys.argv[1], 'wb').write(QEMU_TARGETS['esp32c3'].default_efuse)
PYEFUSE
  ser="$(mktemp)"
  timeout 40 "$QEMU_BIN" -nographic -machine esp32c3 \
    -drive file=build/qemu_flash.bin,if=mtd,format=raw \
    -drive file=build/qemu_efuse.bin,if=none,format=raw,id=efuse \
    -global driver=nvram.esp32c3.efuse,property=drive,value=efuse \
    -serial "file:$ser" </dev/null >/dev/null 2>&1 || true
  got="$(tr -d '\r' < "$ser" | grep '^PXX timer:' || true)"
  want="$(printf 'PXX timer: started\nPXX timer: tick=1\nPXX timer: tick=2\nPXX timer: tick=3\nPXX timer: tick=4\nPXX timer: tick=5\nPXX timer: done ticks=5 status=0')"
  if [ "$got" = "$want" ]; then
    echo "OK   timer-c3 qemu acceptance -- 5 esp_timer callbacks, status=0"
    rm -f "$ser"
  else
    echo "FAIL timer-c3 qemu acceptance"
    echo "want:"; printf '%s\n' "$want" | sed 's/^/    /'
    echo "got:";  printf '%s\n' "$got"  | sed 's/^/    /'
    echo "(full serial log kept at $ser)"
    exit 1
  fi
fi
