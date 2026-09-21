#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (ESP32-C3) ISR-context asymmetry probe. See main/main.pas for
# what this measures and why it is a PAIR rather than a reading.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh              build only
#          ./build.sh qemu         build, then boot under Espressif QEMU
#          ./build.sh qemu-assert  build, boot, ASSERT the pair, non-interactive
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$REPO_ROOT/stable_linux_amd64/default/pinned}"

# --no-signals as well as --platform=esp: the signal runtime's rt_sigaction
# install is an ecall in app_main's prologue, fatal under FreeRTOS.
"$PXX" --target=riscv32 --platform=esp --no-signals -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" main/main.pas main/main.o
ar rcs main/libpxx_app.a main/main.o

# `set-target` WIPES build/ and reconfigures, so it is not run unconditionally.
# The SECOND condition is this example's own: sdkconfig.defaults is only
# consulted when sdkconfig is (re)generated, so a tree configured before that
# file existed -- or copied from timer-c3 -- keeps ISR dispatch OFF and the
# probe then measures a build that cannot have an ISR timer at all. Checking
# the generated sdkconfig for the option itself, rather than assuming the
# defaults file was honoured, is the difference between testing the thing and
# testing that a file exists.
if ! grep -q '^CONFIG_IDF_TARGET="esp32c3"' sdkconfig 2>/dev/null \
   || ! grep -q '^CONFIG_ESP_TIMER_SUPPORTS_ISR_DISPATCH_METHOD=y' sdkconfig 2>/dev/null; then
  rm -f sdkconfig
  idf.py set-target esp32c3
fi
idf.py build

# Cheap structural checks, both of which have caught a real mistake in the
# sibling examples: app_main must actually be in the image, and the ISR
# callback must have landed in IRAM rather than flash.
grep -q " app_main" build/pxx_isrctx_c3.map && echo "app_main present in image map"
if grep -qE '\.iram1[^ ]*[[:space:]]+0x[0-9a-f]+[[:space:]]+0x[0-9a-f]+.*main\.o' build/pxx_isrctx_c3.map \
   || grep -q 'OnIsrTick' build/pxx_isrctx_c3.map; then
  echo "ISR callback symbol present in image map"
fi

if [ "${1:-}" = "qemu" ]; then
  idf.py qemu monitor
fi

# Non-interactive ACCEPTANCE -- same mechanism as timer-c3, and the comments
# there explain why it is driven directly rather than through `idf.py qemu`
# (the app parks forever by design, so a pipeline buffers until the timeout
# kills it and captures nothing).
if [ "${1:-}" = "qemu-assert" ]; then
  QEMU_BIN="${QEMU_BIN:-$HOME/.espressif/tools/qemu-riscv32/esp_develop_9.2.2_20250817/qemu/bin/qemu-system-riscv32}"
  if [ ! -x "$QEMU_BIN" ]; then
    echo "SKIP qemu-assert -- no Espressif qemu-system-riscv32 at $QEMU_BIN"
    echo "     (IDF installs it OFF PATH under ~/.espressif/tools/.)"
    exit 77
  fi
  ( cd build && esptool --chip esp32c3 merge-bin --pad-to-size 2MB \
      -o qemu_flash.bin @flash_args >/dev/null )
  # Defaults, not a blank block: an all-zero efuse reports chip revision v0.0,
  # the image requires >= v0.3, and the bootloader reboots forever -- a serial
  # log full of boot attempts, indistinguishable from an app that printed
  # nothing. Taken from IDF's own table so it cannot rot.
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

  got="$(tr -d '\r' < "$ser" | grep '^PXX isrctx:' || true)"
  echo "serial (PXX lines):"
  printf '%s\n' "$got" | sed 's/^/    /'

  # THE ASSERTION IS THE PAIR, AND IT IS SPELLED OUT HERE RATHER THAN TRUSTED
  # TO status=0 ALONE. The app computes status itself, so `PAIR OK` is a claim
  # by the thing under test; re-deriving the two context readings from the
  # serial text is an independent check that fails differently (a linker or
  # printf fault that garbles the numbers keeps status=0 and breaks these).
  #
  # `<> 0`, NEVER `= 1`: riscv returns the raw nesting count and xtensa a
  # normalised boolean, so a row pinning 1 passes on xtensa and can fail on
  # riscv under nesting. The count is printed, never asserted.
  task_ctx="$(printf '%s\n' "$got" | sed -n 's/^PXX isrctx: task hits=[0-9-]* ctx=\(-\?[0-9]*\)$/\1/p')"
  isr_ctx="$( printf '%s\n' "$got" | sed -n 's/^PXX isrctx: isr  hits=[0-9-]* ctx=\(-\?[0-9]*\)$/\1/p')"
  ok=1
  printf '%s\n' "$got" | grep -q '^PXX isrctx: PAIR OK status=0$' || { echo "  -- app did not report PAIR OK status=0"; ok=0; }
  [ -n "$task_ctx" ] && [ -n "$isr_ctx" ] || { echo "  -- could not parse both ctx readings from the serial log"; ok=0; }
  [ "${task_ctx:-x}" = "0" ] || { echo "  -- task-dispatch ctx is '${task_ctx}', expected 0"; ok=0; }
  [ -n "$isr_ctx" ] && [ "$isr_ctx" -ne 0 ] 2>/dev/null || { echo "  -- ISR-dispatch ctx is '${isr_ctx}', expected NON-ZERO (this is the discriminating half)"; ok=0; }

  if [ "$ok" = "1" ]; then
    echo "OK   isrctx-c3 qemu acceptance -- task ctx=$task_ctx, ISR ctx=$isr_ctx (asymmetry witnessed)"
    rm -f "$ser"
  else
    echo "FAIL isrctx-c3 qemu acceptance"
    echo "(full serial log kept at $ser)"
    exit 1
  fi
fi
