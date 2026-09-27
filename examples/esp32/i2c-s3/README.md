# i2c-s3

**Chip:** ESP32-S3 (Xtensa LX7). **Language:** Pascal (`main/main.pas`), compiled by PXX
into an ESP-IDF application.

The I2C bus (`espi2c`), with the chip's second I2C controller acting as the device. The full test needs two jumper wires, GPIO17 to GPIO15 and GPIO18 to GPIO16; without them only the empty-bus checks run.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/i2c-s3 --port /dev/ttyACM0
```

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
