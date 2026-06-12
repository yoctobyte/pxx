# ESP-IDF integration: Xtensa (ESP32-S2/S3) — QEMU + real hardware

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-elf-rel-writer, feature-xtensa-windowed-abi, feature-esp32-idf-riscv32
- **Opened:** 2026-06-12 (esp32-idf integration plan)

## Motivation

The payoff ticket: PXX-compiled Pascal running on the user's physical
ESP32-S2/S3 boards inside an ESP-IDF app — `app_main` in Pascal, calling
vendor APIs (GPIO/UART/delay) through the IDF link. C3/riscv32 ticket proves
the pipeline shape; this one adds the windowed-ABI object and real hardware.

## Scope

- Reuse the IDF component template from feature-esp32-idf-riscv32 with
  `--target=xtensa --xtensa-abi=windowed --emit-obj`.
- `idf.py set-target esp32s3` build; boot under
  `qemu-system-xtensa -M esp32s3` (Espressif QEMU 9.2.2 installed) first.
- Then real S3 board: `idf.py flash monitor` (dfu-util/esptool installed).
- Demo: serial hello via `esp_rom_printf` + LED blink via
  `gpio_set_direction`/`gpio_set_level` + `vTaskDelay` — all hand-declared
  externals.
- Verify GDB/JTAG acceptance from the original ESP32 ticket on at least one
  path: `idf.py qemu gdb` (or openocd on hardware) shows a sane backtrace
  through windowed Pascal frames.

## Non-goals

- Wi-Fi/networking, NVS, FreeRTOS task creation from Pascal — later arcs.
- C header import (hand decls; feature-c-header-import-complex owns the rest).
- ESP32 classic (LX6) hardware — user boards are S2/S3; QEMU `-M esp32`
  covers LX6 if ever needed.

## Acceptance

- Boots under `qemu-system-xtensa -M esp32s3` with serial output produced by
  Pascal code.
- Same image flashed to a physical S2 or S3 board: serial hello visible in
  `idf.py monitor`, LED blinks.
- Debugger shows call stack through Pascal `app_main`.

## Notes

- ESP-IDF v6.0.1 at ~/esp/esp-idf; xtensa-esp32s2/s3-elf-gcc 15.2.0 and
  Espressif QEMU installed 2026-06-12 (see done/feature-target-esp32 log).
- Flashing needs the board on a real /dev/ttyUSB*/ttyACM* — coordinate with
  the user for the hardware step.
