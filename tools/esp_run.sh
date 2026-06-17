#!/usr/bin/env bash
# Boot a PXX program on the ESP32-C3 (riscv32) under Espressif QEMU and print
# what app_main wrote to the ROM console, with the IDF boot banner stripped.
#
#   tools/esp_run.sh <prog.pas>
#
# The program is compiled with --target=riscv32 to a relocatable object,
# dropped into the examples/esp32/hello-c3 IDF project as the app_main
# provider, linked by the normal IDF build, merged to a flash image, and
# booted under qemu-system-riscv32 -M esp32c3. Stdout is exactly the bytes the
# Pascal program emitted (e.g. via esp_rom_printf), so it can be diffed against
# the program's x86-64 run (the oracle) for output-equality validation.
#
# Prereqs (heavy, not part of `make test`):
#   - ESP-IDF checkout that exports idf.py + toolchains + esptool
#     (default ~/esp/esp-idf; override with ESP_IDF_DIR)
#   - Espressif qemu fork under ~/.espressif/tools/qemu-riscv32
set -euo pipefail

PAS="${1:?usage: tools/esp_run.sh <prog.pas>}"
PAS="$(cd "$(dirname "$PAS")" && pwd)/$(basename "$PAS")"   # absolute; survives cd
TIMEOUT="${ESP_RUN_TIMEOUT:-15}"
ESP_IDF_DIR="${ESP_IDF_DIR:-$HOME/esp/esp-idf}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$REPO_ROOT/examples/esp32/hello-c3"
PXX="$REPO_ROOT/compiler/pascal26"
QEMU="$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1)"

[ -x "$PXX" ] || { echo "esp_run: compiler not built ($PXX)" >&2; exit 2; }
[ -n "$QEMU" ] || { echo "esp_run: Espressif qemu-system-riscv32 not found" >&2; exit 2; }
[ -f "$ESP_IDF_DIR/export.sh" ] || { echo "esp_run: ESP-IDF not at $ESP_IDF_DIR" >&2; exit 2; }

# shellcheck disable=SC1091
. "$ESP_IDF_DIR/export.sh" >/dev/null 2>&1

cd "$PROJ"
"$PXX" --target=riscv32 "$PAS" main/main.o >/dev/null
ar rcs main/libpxx_app.a main/main.o
# Reuse the configured build dir; full reconfigure only if it is missing.
if [ -f build/build.ninja ]; then ninja -C build >/dev/null
else idf.py set-target esp32c3 >/dev/null && idf.py build >/dev/null; fi

cd build
python -m esptool --chip esp32c3 merge-bin -o /tmp/esp_run_flash.bin \
  @flash_args --fill-flash-size 2MB >/dev/null 2>&1

SER="$(mktemp)"
timeout "$TIMEOUT" "$QEMU" -M esp32c3 \
  -drive file=/tmp/esp_run_flash.bin,if=mtd,format=raw \
  -nographic -serial mon:stdio -monitor none >"$SER" 2>&1 || true

# Everything after the IDF "Calling app_main()" line is the program's output,
# minus the trailing qemu "terminating on signal" notice from the timeout kill.
# The esp serial console turns each '\n' into '\r\n'; strip the CR so the bytes
# match a plain-LF Linux oracle run.
awk 'f && !/qemu-system-riscv32: terminating/ {print} /Calling app_main\(\)/{f=1}' "$SER" \
  | tr -d '\r'
rm -f "$SER"
