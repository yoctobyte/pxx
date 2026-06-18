#!/usr/bin/env bash
# Boot a PXX program as a bare-metal ESP32 image (no ESP-IDF) under Espressif
# QEMU and print exactly what the program wrote to UART0.
#
#   tools/esp_run_bare.sh [--chip esp32c3] <prog.pas>
#
# Unlike tools/esp_run.sh (which links a relocatable object into an IDF project
# and boots from a flash image), this compiles a self-contained ET_EXEC linked
# at the SoC SRAM map (--esp-profile=bare) and hands it straight to qemu with
# `-kernel`. The program owns startup (sp init) and output (UART0 TX FIFO MMIO
# at 0x60000000); there is no FreeRTOS, no esp_rom_printf. Stdout is the raw
# serial bytes the program emitted, banner stripped, CR removed -- diff against
# the program's x86-64 run (the oracle) for output-equality validation.
#
# Only esp32c3 (riscv32) is supported today; xtensa bare-boot is pending.
#
# Prereq: Espressif qemu fork under ~/.espressif/tools/qemu-riscv32. Unlike
# esp_run.sh this needs NO ESP-IDF checkout (no idf.py, no esptool, no export.sh).
set -euo pipefail

CHIP=esp32c3
if [ "${1:-}" = "--chip" ]; then CHIP="$2"; shift 2; fi
PAS="${1:?usage: tools/esp_run_bare.sh [--chip esp32c3] <prog.pas>}"
PAS="$(cd "$(dirname "$PAS")" && pwd)/$(basename "$PAS")"
TIMEOUT="${ESP_RUN_TIMEOUT:-8}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PXX="$REPO_ROOT/compiler/pascal26"

case "$CHIP" in
  esp32c3)
    PXXFLAGS="--target=riscv32 --esp-profile=bare"
    QEMU="$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1)" ;;
  *) echo "esp_run_bare: unsupported chip '$CHIP' (only esp32c3; xtensa bare pending)" >&2; exit 2 ;;
esac

[ -x "$PXX" ]  || { echo "esp_run_bare: compiler not built ($PXX)" >&2; exit 2; }
[ -n "$QEMU" ] || { echo "esp_run_bare: Espressif qemu for $CHIP not found" >&2; exit 2; }

ELF="$(mktemp).elf"
# shellcheck disable=SC2086
"$PXX" $PXXFLAGS ${ESP_PXXFLAGS:-} "$PAS" "$ELF" >/dev/null

SER="$(mktemp)"
timeout -s KILL "$TIMEOUT" "$QEMU" -M "$CHIP" -kernel "$ELF" \
  -nographic -serial mon:stdio -monitor none >"$SER" 2>&1 || true

# qemu prints two banner lines ("Not initializing SPI Flash" / "Loading kernel
# at address 0x...") before control reaches our entry; everything after is the
# program's UART output. Drop the trailing qemu "terminating on signal" notice
# the SIGKILL leaves, and strip CR so the bytes match a plain-LF Linux oracle.
awk 'f && !/qemu-system-[a-z0-9]*: terminating/ {print} /Loading kernel at address/{f=1}' "$SER" \
  | tr -d '\r'
rm -f "$SER" "$ELF"
