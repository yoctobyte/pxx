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

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
