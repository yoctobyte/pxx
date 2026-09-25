#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Boot a PXX program on an ESP32 chip under Espressif QEMU and print what
# app_main wrote to the ROM console, with the IDF boot banner stripped.
#
#   tools/esp_run.sh [--chip esp32s3|esp32c3] <prog.pas>
#
# Default chip is esp32s3 (Xtensa, the primary hardware target). The program is
# compiled to a relocatable object for the chip's ISA, dropped into the
# matching examples/esp32 IDF project as the app_main provider, linked by the
# normal IDF build, merged to a flash image, and booted under the Espressif
# qemu fork. Stdout is exactly the bytes the Pascal program emitted (serial
# CRLF normalized to LF), so it can be diffed against the program's x86-64 run
# (the oracle) for output-equality validation.
#
# Per chip:
#   esp32s3 -> --target=esp32s3 (the chip name alone means windowed on IDF
#              since 2026-09-24; it used to need --xtensa-abi=windowed
#              spelled out), project hello-s3,
#              qemu-system-xtensa  -M esp32s3
#   esp32c3 -> --target=riscv32,                       project hello-c3,
#              qemu-system-riscv32 -M esp32c3
#
# Prereqs (heavy, not part of `make test`):
#   - ESP-IDF checkout that exports idf.py + toolchains + esptool
#     (default ~/esp/esp-idf; override with ESP_IDF_DIR)
#   - Espressif qemu forks under ~/.espressif/tools/qemu-{xtensa,riscv32}
set -euo pipefail

CHIP=esp32s3
if [ "${1:-}" = "--chip" ]; then CHIP="$2"; shift 2; fi
PAS="${1:?usage: tools/esp_run.sh [--chip esp32s3|esp32c3] <prog.pas>}"
PAS="$(cd "$(dirname "$PAS")" && pwd)/$(basename "$PAS")"   # absolute; survives cd
TIMEOUT="${ESP_RUN_TIMEOUT:-15}"
ESP_IDF_DIR="${ESP_IDF_DIR:-$HOME/esp/esp-idf}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# ESP_RUN_PXX picks another compiler -- the pinned one, for a control. It is
# NOT spelled PXX: this line used to ignore a PXX from the environment, so
# `PXX=<pinned> tools/esp_run.sh` silently ran HEAD and a pinned-vs-HEAD
# control compared HEAD with itself (measured 2026-09-19, on a fix whose pinned
# control then "passed"). A distinct name cannot be inherited by accident.
PXX="${ESP_RUN_PXX:-$REPO_ROOT/compiler/pascal26}"
echo "esp_run: compiler $PXX" >&2

case "$CHIP" in
  esp32s3)
    PROJ="$REPO_ROOT/examples/esp32/hello-s3"
    PXXFLAGS="--target=esp32s3"
    QEMU="$(ls "$HOME"/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1)" ;;
  esp32c3)
    PROJ="$REPO_ROOT/examples/esp32/hello-c3"
    PXXFLAGS="--target=riscv32 --platform=esp"
    QEMU="$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1)" ;;
  *) echo "esp_run: unknown chip '$CHIP' (esp32s3|esp32c3)" >&2; exit 2 ;;
esac
# ESP_RUN_PROJECT=<name under examples/esp32> links into another IDF project
# with the same main component shape -- nilpy-s3 / nilpy-c3 for a NilPy
# program, whose runtime does not fit hello's stock 1 MB app partition
# ("app partition is too small"). The chip's own flags are unchanged.
if [ -n "${ESP_RUN_PROJECT:-}" ]; then PROJ="$REPO_ROOT/examples/esp32/$ESP_RUN_PROJECT"; fi

[ -x "$PXX" ]    || { echo "esp_run: compiler not built ($PXX)" >&2; exit 2; }
[ -n "$QEMU" ]   || { echo "esp_run: Espressif qemu for $CHIP not found" >&2; exit 2; }
[ -d "$PROJ" ]   || { echo "esp_run: IDF project $PROJ missing" >&2; exit 2; }
[ -f "$ESP_IDF_DIR/export.sh" ] || { echo "esp_run: ESP-IDF not at $ESP_IDF_DIR" >&2; exit 2; }

# shellcheck disable=SC1091
. "$ESP_IDF_DIR/export.sh" >/dev/null 2>&1

# ONE RUN PER PROJECT AT A TIME, AND A FLASH IMAGE OF OUR OWN. Every program
# for a chip is built in the same $PROJ (main/main.o, build/), and the image
# used to go to the fixed /tmp/esp_run_flash.bin, shared by every checkout on
# the box. Measured 2026-09-19: a second esp_run.sh started 10s after a first
# rebuilt the project and rewrote the image before the first qemu booted it,
# so the FIRST run printed the SECOND program's output -- dns-c3's smoke line
# under a timer-c3 invocation, 2 of 2 trials -- and a caller grepping for its
# own "ok" line would have passed a program that never ran. The lock is on
# the project DIRECTORY (no lock file to ignore), held to exit, so it covers
# compile, link, merge and the qemu run that reads the image lazily.
#
# OUT OF TREE since 2026-09-25: the project is staged under $TMPDIR and built
# there (tools/esp_stage.sh says why -- in-tree build/ dirs filled plexus's /),
# so the lock is on the STAGED directory, which is still one per checkout and
# project. The checkout's examples/esp32 is left byte-clean.
# shellcheck disable=SC1091
. "$REPO_ROOT/tools/esp_stage.sh"
STAGED="$(esp_stage_path "$PROJ")"
mkdir -p "$STAGED"
exec 9<"$STAGED"
flock 9
esp_stage_sync "$PROJ" "$STAGED" || { echo "esp_run: staging $PROJ to $STAGED failed" >&2; exit 1; }
FLASH="$(mktemp --suffix=.bin)"
trap 'rm -f "$FLASH"' EXIT

cd "$STAGED"
# The compile runs from INSIDE the project, so any -Fu in ESP_PXXFLAGS must be
# absolute. Its diagnostics used to go to /dev/null along with the "ok:" line,
# so a failed compile aborted with no output at all and looked like a program
# that printed nothing — keep stderr, and say which step died.
# shellcheck disable=SC2086
if ! "$PXX" $PXXFLAGS ${ESP_PXXFLAGS:-} "$PAS" main/main.o >/dev/null; then
  echo "esp_run: compiling $PAS failed (note: -Fu paths must be absolute)" >&2
  exit 1
fi
ar rcs main/libpxx_app.a main/main.o
# The Pascal code arrives via add_prebuilt_library (libpxx_app.a), which ninja
# does NOT track for content changes -- so force a relink by removing the app
# image, or a stale binary from a previous program would boot instead. Build
# errors (e.g. an undefined external) must abort, not silently run the old image.
#
# KEEP THE BUILD OUTPUT ON FAILURE. `>/dev/null` here threw away the only thing
# that says WHY, and `esp_run: build failed` is a verdict with no evidence --
# the same defect the comment above records for the COMPILE step, one step
# later. Measured 2026-09-06: examples/esp32/fs-c3 reported exactly that bare
# line, and the discarded text said `undefined reference to
# esp_vfs_fat_spiflash_mount_rw_wl`, which is what identifies it in one read as
# a project-config mismatch rather than a compiler defect. Without it the
# obvious inference is a pxx bug, and it is not one.
BLOG="$(mktemp)"
build_failed() {
  echo "esp_run: build failed -- last 30 lines of the build log:" >&2
  tail -30 "$BLOG" >&2
  echo "esp_run: (full log: $BLOG)" >&2
  echo "esp_run: NOTE -- every program is built inside the $PROJ project. An" >&2
  echo "         example needing its own partition table or sdkconfig (fs-c3" >&2
  echo "         adds a storage FAT partition) will fail HERE and build fine" >&2
  echo "         under its own build.sh. That is this runner's limit, not the" >&2
  echo "         program's." >&2
  exit 1
}
if [ -f build/build.ninja ]; then
  rm -f build/*.elf build/*.bin
  ninja -C build >"$BLOG" 2>&1 || build_failed
else
  { idf.py set-target "$CHIP" && idf.py build; } >"$BLOG" 2>&1 || build_failed
fi

cd build
# The flash size the PROJECT was configured for, not a constant: the NilPy
# projects' factory partition alone is 3.75 MB, and an image filled to 2 MB
# does not boot -- silently, with no output after the bootloader.
FLASHSZ="$(sed -n 's/^#define CONFIG_ESPTOOLPY_FLASHSIZE "\(.*\)"/\1/p' config/sdkconfig.h 2>/dev/null | head -1)"
python -m esptool --chip "$CHIP" merge-bin -o "$FLASH" \
  @flash_args --fill-flash-size "${FLASHSZ:-2MB}" >/dev/null 2>&1

SER="$(mktemp)"
timeout "$TIMEOUT" "$QEMU" -M "$CHIP" \
  -drive file="$FLASH",if=mtd,format=raw \
  -nographic -serial mon:stdio -monitor none >"$SER" 2>&1 || true

# Everything after the IDF "Calling app_main()" line is the program's output,
# minus the trailing qemu "terminating on signal" notice from the timeout kill.
# The esp serial console turns each '\n' into '\r\n'; strip the CR so the bytes
# match a plain-LF Linux oracle run.
awk 'f && !/qemu-system-[a-z0-9]*: terminating/ {print} /Calling app_main\(\)/{f=1}' "$SER" \
  | tr -d '\r'
rm -f "$SER"
