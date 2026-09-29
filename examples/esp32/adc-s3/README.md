# adc-s3

**Chip:** ESP32-S3 (Xtensa LX7). **Language:** Nil Python (`main/main.npy`), compiled by PXX
into an ESP-IDF application.

Continuous ADC sampling whose frames reach Python outside interrupt context, through the `interrupts` event pump. Nothing wired.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/adc-s3 --port /dev/ttyACM0
```

The expected serial output is `main/main.expected`.

## QEMU

This example needs a board: an ESP32-S3 board, nothing wired. Its `./build.sh qemu-assert` builds and boots, but the program prints nothing under QEMU: Espressif's QEMU does not model the ADC. Checked on 2026-09-29 with v451 (compiler sha256 `d9b7226769cc`) from the release archive.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
