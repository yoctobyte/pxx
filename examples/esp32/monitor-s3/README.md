# monitor-s3

**Chip:** ESP32-S3 (Xtensa LX7). **Language:** Nil Python (`main/main.npy`), compiled by PXX
into an ESP-IDF application.

A sensor monitor: averages background ADC samples, counts presses of the BOOT button and reports the free heap once a second. Walked through in [Getting started on the ESP32](../../../docs/getting-started/esp32.md).

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/monitor-s3 --port /dev/ttyACM0
```

## QEMU

This example needs a board: an ESP32-S3 devkit (it reads the ADC and counts presses of the BOOT button). The project ships no `main/main.expected`, so `./build.sh qemu-assert` stops with `main/main.expected: No such file or directory` after the build. Checked on 2026-09-29 with v451 (compiler sha256 `d9b7226769cc`) from the release archive.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
