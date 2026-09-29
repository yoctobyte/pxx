# nvs-s3

**Chip:** ESP32-S3 (Xtensa LX7). **Language:** Pascal (`main/main.pas`), compiled by PXX
into an ESP-IDF application.

Settings that survive a reboot (`espnvs`), checked across four boots, the last after a hardware reset. Needs a real board.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/nvs-s3 --port /dev/ttyACM0
```

## QEMU

This example needs a board: an ESP32-S3 board. `build.sh` has no QEMU mode; the test's last boot follows a hardware reset.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
