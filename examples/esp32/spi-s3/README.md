# spi-s3

**Chip:** ESP32-S3 (Xtensa LX7). **Language:** Pascal (`main/main.pas`), compiled by PXX
into an ESP-IDF application.

The SPI master (`espspi`) on SPI2, checked with no device and no wire.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/spi-s3 --port /dev/ttyACM0
```

## Run under QEMU

No board needed. From this directory in the release archive, with Espressif's QEMU installed (see [ESP32](../../../docs/targets/esp32.md)):

```sh
. ~/esp/esp-idf/export.sh
./build.sh qemu-assert
```

Checked on 2026-09-29 with v451 (compiler sha256 `d9b7226769cc`) from the release archive, under Espressif's QEMU, not on a board: `./build.sh qemu-assert` ended with `OK   spi-s3 -- bus and devices open under qemu, output == main/qemu.expected, one boot` after about 4 minutes. Under QEMU the bus and devices open but nothing answers, so it compares with `main/qemu.expected`; `main/main.expected` is for a board.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
