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

# `set-target` WIPES build/ and reconfigures, so running it unconditionally
# turns every invocation into a from-scratch ~1053-target rebuild (minutes), and
# it also deletes the qemu flash/efuse images between a build and an assert.
# Only run it when the tree is not already configured for this chip. (Same
# guard as timer-c3; it was the first of the three harness bugs there.)
if ! grep -q '^CONFIG_IDF_TARGET="esp32s3"' sdkconfig 2>/dev/null; then
  idf.py set-target esp32s3
fi
idf.py build

grep -q " app_main" build/pxx_timer_s3.map && echo "app_main present in image map"

if [ "${1:-}" = "qemu" ]; then
  idf.py qemu monitor
fi

# Non-interactive ACCEPTANCE for the S3 (xtensa). Ported from timer-c3's
# qemu-assert, which is the version that is green; every deviation below is a
# real per-chip difference taken from IDF's own QEMU_TARGETS table, not a
# guess:
#
#   qemu binary   qemu-system-xtensa, not -riscv32 (different install package)
#   machine       -M esp32s3 -m 32M   -- the S3 entry carries the -m, the C3's
#                 does not, and QEMU will not boot the image without it
#   strap/efuse   driver names are per-target (nvram.esp32s3.efuse)
#   wdt + nic     IDF adds a wdt_disable global and a user-mode NIC on every
#                 target; the C3 script omitted both and still passed, but an
#                 S3 first run should not also be the experiment in dropping
#                 them
#
# THE FAILURE MODE TO EXPECT IS AN EMPTY LOG, NOT AN ERROR. Two harness bugs
# cost frankB three attempts on the C3 and both present identically: a missing
# flash image (set-target wipes build/), and an all-zero efuse block, which
# reports chip revision v0.0 against an image needing >= v0.3 so the bootloader
# rejects and reboots forever. Either produces "no PXX lines" -- which on THIS
# lane is indistinguishable from the managed-string bugs whose signature is
# printing nothing. Check the log's SIZE and its boot banner before concluding
# anything about codegen.
if [ "${1:-}" = "qemu-assert" ]; then
  QEMU_BIN="${QEMU_BIN:-$HOME/.espressif/tools/qemu-xtensa/esp_develop_9.2.2_20250817/qemu/bin/qemu-system-xtensa}"
  if [ ! -x "$QEMU_BIN" ]; then
    echo "SKIP qemu-assert -- no Espressif qemu-system-xtensa at $QEMU_BIN"
    echo "     (IDF installs it OFF PATH under ~/.espressif/tools/; a bare"
    echo "      \`command -v qemu-system-xtensa\` cannot see it and will"
    echo "      wrongly report the machine has no runner.)"
    exit 77
  fi
  ( cd build && esptool --chip esp32s3 merge-bin --pad-to-size 2MB \
      -o qemu_flash.bin @flash_args >/dev/null )
  python3 - "$PWD/build/qemu_efuse.bin" <<'PYEFUSE'
import sys, os
sys.path.insert(0, os.path.join(os.environ['IDF_PATH'], 'tools'))
from idf_py_actions.qemu_ext import QEMU_TARGETS
open(sys.argv[1], 'wb').write(QEMU_TARGETS['esp32s3'].default_efuse)
PYEFUSE
  ser="$(mktemp)"
  timeout 60 "$QEMU_BIN" -nographic -M esp32s3 -m 32M \
    -drive file=build/qemu_flash.bin,if=mtd,format=raw \
    -drive file=build/qemu_efuse.bin,if=none,format=raw,id=efuse \
    -global driver=nvram.esp32s3.efuse,property=drive,value=efuse \
    -global driver=timer.esp32s3.timg,property=wdt_disable,value=true \
    -nic user,model=open_eth \
    -serial "file:$ser" </dev/null >/dev/null 2>&1 || true
  got="$(tr -d '\r' < "$ser" | grep '^PXX timer:' || true)"
  want="$(printf 'PXX timer: started\nPXX timer: tick=1\nPXX timer: tick=2\nPXX timer: tick=3\nPXX timer: tick=4\nPXX timer: tick=5\nPXX timer: done ticks=5 status=0')"
  if [ "$got" = "$want" ]; then
    echo "OK   timer-s3 qemu acceptance -- 5 esp_timer callbacks on emulated XTENSA, status=0"
    rm -f "$ser"
  else
    echo "FAIL timer-s3 qemu acceptance"
    echo "serial log is $(wc -c < "$ser") bytes -- if that is ~0 the image or the"
    echo "efuse is wrong, NOT the compiler; if it is large and has no PXX lines,"
    echo "look for a reboot loop in it before blaming codegen."
    echo "want:"; printf '%s\n' "$want" | sed 's/^/    /'
    echo "got:";  printf '%s\n' "$got"  | sed 's/^/    /'
    echo "(full serial log kept at $ser)"
    exit 1
  fi
fi
