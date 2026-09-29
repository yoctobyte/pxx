# nilpy-hw-s3

**Chip:** ESP32-S3 (Xtensa LX7). **Language:** Nil Python (`main/main.npy`), compiled by PXX
into an ESP-IDF application.

A Python program that drives a GPIO pin and is driven by an ESP-IDF timer callback. The same source as `nilpy-hw-c3`.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/nilpy-hw-s3 --port /dev/ttyACM0
```

The expected serial output is `main/main.expected`.

## Run under QEMU

No board needed. From this directory in the release archive, with Espressif's QEMU installed (see [ESP32](../../../docs/targets/esp32.md)):

```sh
. ~/esp/esp-idf/export.sh
./build.sh qemu-assert
```

Checked on 2026-09-29 with v451 (compiler sha256 `d9b7226769cc`) from the release archive, under Espressif's QEMU, not on a board: `./build.sh qemu-assert` ended with `OK   nilpy-hw-s3 -- a static Python application runs on the esp32s3, output == main/main.expected, one boot` after about 6 minutes.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
