#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# PXX -> ESP-IDF: a static Python application. main/main.npy is compiled by
# pxx's NilPy frontend to a relocatable object for the chip's ISA, wrapped in
# an archive, and linked by the normal IDF build. There is no interpreter on
# the chip.
#
# ONE script, one project per (program, chip): nilpy-c3 / nilpy-s3 are the
# `print` demo on the ESP32-C3 (riscv32) and ESP32-S3 (xtensa), nilpy-hw-c3 /
# nilpy-hw-s3 the hardware one. Each directory holds a symlink to this script
# and to the program, so the two chips always build the same source. IDF wants
# one project per chip (set-target wipes build/), which is why the directories
# are per chip at all.
#
# Prereqs: . ~/esp/esp-idf/export.sh   (idf.py + toolchains on PATH)
# Usage:   ./build.sh               build only
#          ./build.sh qemu-assert   build, boot under Espressif QEMU, and diff
#                                   the program's output against
#                                   main/main.expected
#          ./build.sh sram          build, boot, and report SRAM: our object's
#                                   data+bss, and the DRAM the chip's own
#                                   heap_init says is LEFT after the whole link
#
# Its OWN project, not tools/esp_run.sh's hello-*, for the same reason as
# fs-c3: it needs its own partition table. The NilPy runtime is ~3 MB of code
# without --dce and the stock 1 MB factory app partition cannot hold it, so
# this project is 4 MB of flash with one large app (partitions.csv). Code is
# FLASH on this profile; SRAM is data+bss, ~175 KB here.
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../../.. && pwd)"
PXX="${PXX:-$REPO_ROOT/stable_linux_amd64/default/pinned}"

# The chip comes from the directory's SUFFIX and the IDF project name from the
# whole directory name, so a new demo is a new directory plus two symlinks --
# `nilpy-c3`, `nilpy-s3`, `nilpy-hw-c3`, `nilpy-hw-s3` all run this one script.
NAME="pxx_$(basename "$PWD" | tr - _)"
case "$(basename "$PWD")" in
  *-c3)
    CHIP=esp32c3
    # --no-signals as well as --platform=esp: the signal runtime's
    # rt_sigaction install is an ecall in app_main's prologue, fatal under
    # FreeRTOS.
    ISA="--target=riscv32"
    QEMU_GLOB="qemu-riscv32/*/qemu/bin/qemu-system-riscv32" ;;
  *-s3)
    CHIP=esp32s3
    # --xtensa-long-calls: a 2.9 MB image puts forward calls past CALL8's
    # +-512 KiB, and a forward call site is sized before its body exists.
    # feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image
    ISA="--target=xtensa --xtensa-abi=windowed --xtensa-long-calls"
    QEMU_GLOB="qemu-xtensa/*/qemu/bin/qemu-system-xtensa" ;;
  *) echo "build.sh: the directory name must end in -c3 or -s3, not $(basename "$PWD")" >&2; exit 2 ;;
esac

# PXX_EXTRA_FLAGS is for measuring a flag against this program without editing
# the recipe -- `PXX_EXTRA_FLAGS=--dce ./build.sh qemu-assert` is what the DCE
# rows in bug-a-dce-drops-a-called-body-on-the-riscv32-idf-profile were taken
# with. It is NOT how the demo is built.
# The `ok: ... [code= data= bss=]` line is CAPTURED as well as printed: `sram`
# mode reads data/bss off it, and every other mode must still see it on stdout.
# Captured into a variable rather than a temp file so there is nothing to clean
# up; `set -e` still aborts here if the compile fails.
#
# PXX_MAIN swaps the PROGRAM for the same reason: `sram` mode's positive control
# is a copy of main.npy holding a known-size static array, and it has to be
# compiled and linked by this exact recipe or it measures a different build.
# It is only honest in `sram` mode -- main/main.expected still describes
# main.npy, so qemu-assert with a swapped program compares the wrong things.
MAIN_SRC="${PXX_MAIN:-main/main.npy}"
# shellcheck disable=SC2086
PXX_OUT="$("$PXX" $ISA ${PXX_EXTRA_FLAGS:-} --platform=esp --no-signals -Fu"$REPO_ROOT/lib/rtl" -Fu"$REPO_ROOT/lib/rtl/platform/esp" "$MAIN_SRC" main/main.o)"
printf '%s\n' "$PXX_OUT"
PXX_SIZE_LINE="$(printf '%s\n' "$PXX_OUT" | grep -a '^ok:' | tail -1)"
ar rcs main/libpxx_app.a main/main.o

# `set-target` WIPES build/ and reconfigures -- only when not configured yet.
if ! grep -q "^CONFIG_IDF_TARGET=\"$CHIP\"" sdkconfig 2>/dev/null; then
  idf.py set-target "$CHIP"
fi
# ninja does not see inside the prebuilt archive; drop the image to force a
# relink, or a previous program's binary would boot instead.
rm -f build/*.elf build/*.bin
idf.py build

grep -q " app_main" "build/$NAME.map" && echo "app_main present in image map"

# Non-interactive acceptance, the fs-c3 recipe: serial to a FILE, let the
# timeout fire, assert on what was captured.
#
# WHAT A PASS WITNESSES: the program's stdout on an emulated chip, under
# FreeRTOS, is byte-identical to main/main.expected, and the chip booted ONCE
# -- a program that ends by busy-parking starves the idle task and the
# watchdogs reboot it, which replays the output. WHAT IT DOES NOT: silicon.
#
# WHERE main.expected COMES FROM is per demo and it matters: for nilpy-c3 /
# nilpy-s3 it is CPython's own output for the same file, so a pass is a
# differential against CPython. nilpy-hw-* imports two pxx Pascal units that
# CPython has no equivalent of, so there its expected output is the program's
# SPECIFICATION and the oracle claim is weaker -- what it still witnesses is
# that the SDK timer callback fired and the Python loop saw it.
# ONE boot, two callers: `qemu-assert` diffs the program's output, `sram` reads
# IDF's own heap_init lines out of the same log. Lifted into a function so the
# two cannot drift -- an SRAM number measured from a differently-booted image
# would be a number about a different chip state.
boot_capture() {   # $1 = where to write the serial log
  # shellcheck disable=SC2086
  QEMU_BIN="${QEMU_BIN:-$(ls "$HOME"/.espressif/tools/$QEMU_GLOB 2>/dev/null | head -1)}"
  if [ -z "$QEMU_BIN" ] || [ ! -x "$QEMU_BIN" ]; then
    echo "SKIP -- no Espressif qemu for $CHIP under ~/.espressif/tools"
    exit 77
  fi
  ( cd build && esptool --chip "$CHIP" merge-bin --pad-to-size 4MB \
      -o qemu_flash.bin @flash_args >/dev/null )
  ser="$1"
  if [ "$CHIP" = esp32c3 ]; then
    # DEFAULT efuse, not a blank one: an all-zero block reports chip revision
    # v0.0, the bootloader rejects the image and reboots forever
    # (fs-c3/build.sh). The esp32s3 machine boots without one.
    python3 - "$PWD/build/qemu_efuse.bin" <<'PYEFUSE'
import sys, os
sys.path.insert(0, os.path.join(os.environ['IDF_PATH'], 'tools'))
from idf_py_actions.qemu_ext import QEMU_TARGETS
open(sys.argv[1], 'wb').write(QEMU_TARGETS['esp32c3'].default_efuse)
PYEFUSE
    timeout 40 "$QEMU_BIN" -nographic -machine esp32c3 \
      -drive file=build/qemu_flash.bin,if=mtd,format=raw \
      -drive file=build/qemu_efuse.bin,if=none,format=raw,id=efuse \
      -global driver=nvram.esp32c3.efuse,property=drive,value=efuse \
      -serial "file:$ser" </dev/null >/dev/null 2>&1 || true
  else
    timeout 40 "$QEMU_BIN" -nographic -machine esp32s3 \
      -drive file=build/qemu_flash.bin,if=mtd,format=raw \
      -serial "file:$ser" </dev/null >/dev/null 2>&1 || true
  fi
}

if [ "${1:-}" = "qemu-assert" ]; then
  ser="$(mktemp)"
  trap 'rm -f "$ser"' EXIT
  boot_capture "$ser"
  # The program's output is everything after IDF's "Calling app_main()" line,
  # minus IDF's own log lines ("I (123) tag: ...").
  got="$(tr -d '\r' < "$ser" | awk 'f && !/^[IWE] \([0-9]+\) / {print} /Calling app_main\(\)/{f=1}')"
  want="$(cat main/main.expected)"
  boots="$(grep -c 'ESP-ROM' "$ser" || true)"
  if [ "$got" = "$want" ] && [ "$boots" = 1 ]; then
    echo "OK   $(basename "$PWD") -- a static Python application runs on the $CHIP, output == main/main.expected, one boot"
  else
    echo "FAIL $(basename "$PWD") -- output differs from main/main.expected or the chip rebooted (boots=$boots)"
    echo "want:"; printf '%s\n' "$want" | sed 's/^/    /'
    echo "got:";  printf '%s\n' "$got"  | sed 's/^/    /'
    echo "serial tail:"; tr -d '\r' < "$ser" | tail -25 | sed 's/^/    /'
    exit 1
  fi
fi

if [ "${1:-}" = "sram" ]; then
  # WHY THE CHIP AND NOT `idf.py size`: on this profile .text is flash-mapped,
  # so a section total is not an SRAM figure and `size`'s "Total" is not the
  # chip's. What IDF's own heap_init prints is the DRAM left over AFTER every
  # static allocation in the whole link -- ours, the RTL's, FreeRTOS's and the
  # SDK's. It is a measurement of the built image on the emulated part, and it
  # is the complement of the number we actually care about, which is why it
  # moves when anything static moves.
  #
  # THE READOUT CANNOT COLLIDE WITH A BLANK. A missing line is an ERROR here,
  # never a 0: a pool of zero and a pool never parsed would otherwise print the
  # same, and 0 is also what a failed boot gives. Per-region rows are printed so
  # a plausible total made of one wrong region is visible.
  ser="$(mktemp)"
  trap 'rm -f "$ser"' EXIT
  boot_capture "$ser"
  regions="$(tr -d '\r' < "$ser" | grep -a 'heap_init: At ' || true)"
  if [ -z "$regions" ]; then
    echo "FAIL sram -- the boot log has no heap_init line, so there is NO pool figure."
    echo "serial tail:"; tr -d '\r' < "$ser" | tail -25 | sed 's/^/    /'
    exit 1
  fi
  echo "--- SRAM  $(basename "$PWD")  $CHIP  ${PXX_EXTRA_FLAGS:-(no extra flags)}  $MAIN_SRC"
  echo "our object: $PXX_SIZE_LINE"
  printf '%s\n' "$regions" | sed 's/^/  /'
  # Shell arithmetic, not awk: mawk (make's awk on this box) has no strtonum,
  # and an awk that silently reads "0x14900" as 0 would print a plausible small
  # total instead of failing -- the exact collision this mode is built to avoid.
  # Split on the WORDS, not on a field number: the log's leading columns differ
  # between chips and IDF versions, and an off-by-one field index reads `len`
  # as the hex value and dies -- or, worse on another line shape, reads a
  # neighbouring number and totals something real-looking.
  dram=0; rtc=0
  while IFS= read -r line; do
    hex="${line#*len }"; hex="${hex%% *}"
    name="${line##*: }"
    case "$hex" in *[!0-9A-Fa-f]*|'') echo "FAIL sram -- no hex length in: $line"; exit 1;; esac
    n=$((16#$hex))
    case "$name" in *RTCRAM*) rtc=$((rtc + n));; *) dram=$((dram + n));; esac
  done <<< "$regions"
  [ "$dram" -gt 0 ] || { echo "FAIL sram -- parsed a DRAM pool of 0 from $(printf '%s' "$regions" | wc -l) region lines"; exit 1; }
  printf 'free DRAM pool  %d B (%d KiB)\n' "$dram" "$((dram / 1024))"
  printf 'free RTCRAM     %d B\n' "$rtc"
fi
