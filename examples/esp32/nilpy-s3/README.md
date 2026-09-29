# nilpy-s3

**Chip:** ESP32-S3 (Xtensa LX7). **Language:** Nil Python (`main/main.npy`), compiled by PXX
into an ESP-IDF application.

A small Python program (a class, a list of instances, a loop, `print`) compiled to machine code. The same source as `nilpy-c3` and `nilpy-esp32`.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, boot it under Espressif's QEMU with no board, and compare its output
with `main/main.expected` (QEMU is not in a default ESP-IDF install: see
"Running without a board" in [ESP32](../../../docs/targets/esp32.md)):

```sh
. ~/esp/esp-idf/export.sh
./build.sh qemu-assert
```

The first run takes about 3 minutes, most of it ESP-IDF building itself, and
ends with a line that starts `OK   nilpy-s3`.

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/nilpy-s3 --port /dev/ttyACM0
```

The expected serial output is `main/main.expected`.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
