# ESP-IDF integration: Xtensa (ESP32-S2/S3) — QEMU + real hardware

- **Type:** feature
- **Status:** backlog
- **Owner:** —
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
- 2026-06-12 — QEMU path works. `examples/esp32/hello-s3` compiles Pascal
  `app_main` with `--target=xtensa --xtensa-abi=windowed`, archives it as
  `libpxx_app.a`, links via `add_prebuilt_library` + `-u app_main`, and boots
  under `qemu-system-xtensa -M esp32s3`. Serial output:
  `PXX hello from Pascal S3: i=1..5`, `PXX S3 sum 1..5 = 15`, then the app
  parks in a `vTaskDelay`/GPIO blink loop. Link map shows
  `app_main` at `0x4200cfcc`.
- 2026-06-17 — QEMU feature coverage proven well beyond the flat hello, via
  `tools/esp_run.sh --chip esp32s3` (feature-esp32-managed-features): native
  div/mod, the windowed-ABI constant-sp fix (nested/recursive calls), heap,
  dynamic arrays, and array-of-const writeln all run on `-M esp32s3` with output
  identical to x86-64.
- 2026-06-21 — **re-verified on the current compiler (pinned v32, after the
  esp-float arc touched xtensa codegen/parser): NO regression.**
  `examples/esp32/hello-s3/build.sh` rebuilds `main.o` -> `libpxx_app.a` ->
  `idf.py build` clean; `app_main` present in the image map; QEMU boot
  (`qemu-system-xtensa -M esp32s3`) prints the full IDF banner, `Calling
  app_main()`, then `PXX hello from Pascal S3: i=1..5` and `PXX S3 sum 1..5 = 15`.
  **GDB backtrace through windowed Pascal frames CONFIRMED** (acceptance item):
  `xtensa-esp32s3-elf-gdb` on the gdbstub (`-gdb tcp::PORT -S`), `tbreak app_main`
  fires (breakpoints work on the IDF path, unlike the bare-metal raw-ELF gdbstub),
  `bt` shows `#0 app_main  #1 main_task (app_startup.c:199)  #2 vPortTaskWrapper
  (port.c:143)` with a sane sp. The demo's GPIO blink (gpio_set_direction/level)
  + vTaskDelay externals execute in QEMU.
  **ONLY remaining = physical S2/S3 hardware** (`idf.py -p /dev/ttyUSB* flash
  monitor`, eyeball the LED blink, optional openocd backtrace). Needs the user's
  board on a USB port — cannot be done in the agent harness. See the hand-off
  note below.

## Hardware flash hand-off (user runs, needs the board on USB)

```sh
. ~/esp/esp-idf/export.sh
make -C <repo> compiler/pascal26              # ensure current compiler
cd examples/esp32/hello-s3 && ./build.sh      # build with the live PXX
idf.py -p /dev/ttyUSB0 flash monitor          # adjust port (ttyUSB*/ttyACM*)
```
Expect: IDF boot banner, `PXX hello from Pascal S3: i=1..5`, `PXX S3 sum 1..5 = 15`,
then GPIO2 LED toggling on a ~500 ms cadence. Ctrl-] exits the monitor. (Wire an
LED+resistor to GPIO2/GND if the board has no on-board LED there.)

## CLOSED via triage (2026-06-30)

Harness-achievable scope COMPLETE: ESP-IDF Xtensa QEMU path + GDB windowed-frame backtrace done & re-verified. The sole remaining acceptance item — flashing a physical ESP32-S2/S3 board over USB — is un-automatable in this harness. Closing the QEMU/integration scope; physical-board validation split to [[feature-esp-hardware-flash-validation]].
