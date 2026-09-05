#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Boot a PXX program as a bare-metal ESP32 image (no ESP-IDF) under Espressif
# QEMU and print exactly what the program wrote to UART0.
#
#   tools/esp_run_bare.sh [--chip esp32c3|esp32s3] <prog.pas>
#
# Unlike tools/esp_run.sh (which links a relocatable object into an IDF project
# and boots from a flash image), this compiles a self-contained ET_EXEC linked
# at the SoC SRAM map (--esp-profile=bare) and hands it straight to qemu with
# `-kernel`. The program owns startup (sp init) and output (UART0 TX FIFO MMIO
# at 0x60000000); there is no FreeRTOS, no esp_rom_printf. Stdout is the raw
# serial bytes the program emitted, banner stripped, CR removed -- diff against
# the program's x86-64 run (the oracle) for output-equality validation.
#
#   esp32c3 -> --target=riscv32 (Call0 N/A), qemu-system-riscv32 -M esp32c3
#   esp32s3 -> --target=xtensa  (Call0),     qemu-system-xtensa  -M esp32s3
#
# Prereq: Espressif qemu fork under ~/.espressif/tools/qemu-{riscv32,xtensa}.
# Unlike esp_run.sh this needs NO ESP-IDF checkout (no idf.py/esptool/export.sh).
set -euo pipefail

CHIP=esp32c3
if [ "${1:-}" = "--chip" ]; then CHIP="$2"; shift 2; fi
PAS="${1:?usage: tools/esp_run_bare.sh [--chip esp32c3|esp32s3] <prog.pas>}"
PAS="$(cd "$(dirname "$PAS")" && pwd)/$(basename "$PAS")"
TIMEOUT="${ESP_RUN_TIMEOUT:-8}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PXX="$REPO_ROOT/compiler/pascal26"

case "$CHIP" in
  esp32c3)
    PXXFLAGS="--target=riscv32 --esp-profile=bare"
    QEMU="$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1)" ;;
  esp32s3)
    PXXFLAGS="--target=xtensa --esp-profile=bare"
    QEMU="$(ls "$HOME"/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1)" ;;
  *) echo "esp_run_bare: unsupported chip '$CHIP' (esp32c3|esp32s3)" >&2; exit 2 ;;
esac

[ -x "$PXX" ]  || { echo "esp_run_bare: compiler not built ($PXX)" >&2; exit 2; }
[ -n "$QEMU" ] || { echo "esp_run_bare: Espressif qemu for $CHIP not found" >&2; exit 2; }

ELF="$(mktemp).elf"
# Capture the build rather than discarding it. pascal26 writes DIAGNOSTICS TO
# STDOUT, so the previous `>/dev/null` destroyed the reason for every failed
# build -- and because this script's whole output contract is "the bytes the
# program wrote to UART", a build failure and a program that ran and printed
# nothing produced the IDENTICAL observation: empty stdout, nonzero rc.
#
# That is not hypothetical. test-esp-bare's esp32c3 exception row was read as a
# device-side fault and survived a repro at ESP_RUN_TIMEOUT=40 and a second chip
# before a by-hand compile showed `unresolved forward: PXXClassFinalize` -- a
# build error the runner had been swallowing all along. On success this still
# prints nothing, so the UART contract is unchanged.
# shellcheck disable=SC2086
if ! "$PXX" $PXXFLAGS ${ESP_PXXFLAGS:-} "$PAS" "$ELF" >"$ELF.buildlog" 2>&1; then
  echo "esp_run_bare: $CHIP build FAILED for $PAS" >&2
  cat "$ELF.buildlog" >&2
  exit 1
fi

SER="$(mktemp)"
timeout -s KILL "$TIMEOUT" "$QEMU" -M "$CHIP" -kernel "$ELF" \
  -nographic -serial mon:stdio -monitor none >"$SER" 2>&1 || true

# qemu prints a few banner lines before control reaches our entry (the set
# differs per chip: c3 has "Loading kernel at address 0x...", the xtensa fork
# instead warns about -bios/-kernel). Drop the known banner lines plus the
# trailing "terminating on signal" notice the SIGKILL leaves, and strip CR so
# the bytes match a plain-LF Linux oracle. What remains is the program's UART
# output.
grep -vE '^(Not initializing SPI Flash|Warning: both -bios and -kernel|Only loading the the -kernel file|Loading kernel at address |qemu-system-[a-z0-9]*: terminating)' "$SER" \
  | tr -d '\r'
rm -f "$SER" "$ELF"
