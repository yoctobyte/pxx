#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF (classic ESP32, Xtensa LX6) esptimer demo: the same source as
# examples/esp32/timer-c3 and timer-s3, compiled for the THIRD chip. The point
# is the one timer-s3 already makes -- the event surface (TimerInit /
# OnElapsed / TimerStartPeriodicMs) and a callback taken with @ are ABI-portable
# -- extended to the LX6, whose windowed ABI is the S3's but whose memory map
# and peripheral set are not.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh                build only
#          ./build.sh qemu           build, then boot under Espressif QEMU
#          ./build.sh qemu-assert    build, boot, and diff the timer lines
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$("$REPO_ROOT/tools/pxx_stable.sh")}"  # the pin in a checkout, compiler/pxx-<arch> in a release

# --target=esp32, THE CHIP NAME, not `--target=xtensa --xtensa-abi=windowed`
# as timer-s3 spells it. Same reason hello-esp32 gives: the generic xtensa
# spelling answers the S3's memory map, and this is an LX6; the chip name also
# implies the windowed ABI on the IDF platform, so the separate --xtensa-abi is
# redundant here.
#
# --no-signals as well as --platform=esp: the signal runtime's rt_sigaction
# install runs in app_main's prologue, which is fatal under FreeRTOS.
#
# NO --xtensa-long-calls here, and that is a size statement rather than a chip
# one. The NilPy examples need it on this chip (examples/esp32/nilpy-c3/build.sh
# records pin v441 refusing "the forward call to PyUtf8CpAt at code offset
# 501172 cannot reach its body at 1144424"), because their runtime is over a
# megabyte of code. This object is ~30 KB, so every forward call reaches. If you
# copy this script for something larger and hit that refusal, add the flag --
# it is not evidence of an LX6 defect; --target=esp32s3 refuses identically for
# the identical source.
"$PXX" --target=esp32 --platform=esp --no-signals \
  -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" \
  main/main.pas main/main.o
xtensa-esp32-elf-ar rcs main/libpxx_app.a main/main.o

# `set-target` WIPES build/ and reconfigures, so running it unconditionally
# turns every invocation into a from-scratch rebuild (minutes), and it also
# deletes the qemu flash/efuse images between a build and an assert. Only run it
# when the tree is not already configured for this chip. (Same guard as
# timer-c3 and timer-s3; it was the first of the three harness bugs on the C3.)
if ! grep -q '^CONFIG_IDF_TARGET="esp32"' sdkconfig 2>/dev/null; then
  idf.py set-target esp32
fi
idf.py build

grep -q " app_main" build/pxx_timer_esp32.map && echo "app_main present in image map"

if [ "${1:-}" = "qemu" ]; then
  idf.py qemu monitor
fi

# Non-interactive ACCEPTANCE for the classic ESP32. Ported from timer-s3's
# qemu-assert, which is the xtensa version that is green. Every deviation is a
# per-chip difference, not a guess:
#
#   machine       -M esp32. `qemu-system-xtensa -machine help` lists esp32 and
#                 esp32s3, so the same binary serves both; only the -M changes.
#   -m 32M        NOT passed. The S3's IDF entry carries it and the C3's does
#                 not; the classic ESP32 has 4MB of external PSRAM at most and
#                 QEMU's esp32 machine sets its own default, so forcing 32M
#                 describes a machine that does not exist.
#   strap/efuse   driver names are per-target: nvram.esp32.efuse.
#
# THE FAILURE MODE TO EXPECT IS AN EMPTY LOG, NOT AN ERROR -- the same trap the
# other two scripts record. A missing flash image (set-target wipes build/) and
# an all-zero efuse block both produce "no PXX lines", which is
# indistinguishable from a program that ran and printed nothing. Check the log's
# SIZE and its boot banner before concluding anything about codegen.
if [ "${1:-}" = "qemu-assert" ]; then
  QEMU_BIN="${QEMU_BIN:-$HOME/.espressif/tools/qemu-xtensa/esp_develop_9.2.2_20250817/qemu/bin/qemu-system-xtensa}"
  if [ ! -x "$QEMU_BIN" ]; then
    echo "SKIP qemu-assert -- no Espressif qemu-system-xtensa at $QEMU_BIN"
    echo "     (IDF installs it OFF PATH under ~/.espressif/tools/; a bare"
    echo "      \`command -v qemu-system-xtensa\` cannot see it and will"
    echo "      wrongly report the machine has no runner.)"
    exit 77
  fi
  ( cd build && esptool --chip esp32 merge-bin --pad-to-size 4MB \
      -o qemu_flash.bin @flash_args >/dev/null )
  python3 - "$PWD/build/qemu_efuse.bin" <<'PYEFUSE'
import sys, os
sys.path.insert(0, os.path.join(os.environ['IDF_PATH'], 'tools'))
from idf_py_actions.qemu_ext import QEMU_TARGETS
open(sys.argv[1], 'wb').write(QEMU_TARGETS['esp32'].default_efuse)
PYEFUSE
  ser="$(mktemp)"
  timeout 60 "$QEMU_BIN" -nographic -M esp32 \
    -drive file=build/qemu_flash.bin,if=mtd,format=raw \
    -drive file=build/qemu_efuse.bin,if=none,format=raw,id=efuse \
    -global driver=nvram.esp32.efuse,property=drive,value=efuse \
    -nic user,model=open_eth \
    -serial "file:$ser" </dev/null >/dev/null 2>&1 || true
  got="$(tr -d '\r' < "$ser" | grep '^PXX timer:' || true)"
  want="$(printf 'PXX timer: started\nPXX timer: tick=1\nPXX timer: tick=2\nPXX timer: tick=3\nPXX timer: tick=4\nPXX timer: tick=5\nPXX timer: done ticks=5 status=0')"
  if [ "$got" = "$want" ]; then
    echo "OK   timer-esp32 qemu acceptance -- 5 esp_timer callbacks on an emulated LX6, status=0"
    rm -f "$ser"
  else
    echo "FAIL timer-esp32 qemu acceptance"
    echo "serial log is $(wc -c < "$ser") bytes -- if that is ~0 the image or the"
    echo "efuse is wrong, NOT the compiler; if it is large and has no PXX lines,"
    echo "look for a reboot loop in it before blaming codegen."
    echo "want:"; printf '%s\n' "$want" | sed 's/^/    /'
    echo "got:";  printf '%s\n' "$got"  | sed 's/^/    /'
    echo "(full serial log kept at $ser)"
    exit 1
  fi
fi
