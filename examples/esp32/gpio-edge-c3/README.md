# gpio-edge-c3

**Chip:** ESP32-C3 (RISC-V, RV32IMC). **Language:** Nil Python (`main/main.npy`), compiled by PXX
into an ESP-IDF application.

GPIO edge interrupts delivered to a Python handler outside interrupt context, all accounted for. Nothing wired.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/gpio-edge-c3 --port /dev/ttyACM0
```

The expected serial output is `main/main.expected`.

## QEMU

This example needs a board: an ESP32-C3 board. Under QEMU the program runs to `GPIO-EDGE-DONE` but sees no edges (`armed 0`, `isr 0`), so `./build.sh qemu-assert` reports FAIL: QEMU models no GPIO input. Checked on 2026-09-29 with v451 (compiler sha256 `d9b7226769cc`) from the release archive.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
