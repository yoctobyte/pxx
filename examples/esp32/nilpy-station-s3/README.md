# nilpy-station-s3

**Chip:** ESP32-S3 (Xtensa LX7). **Language:** Nil Python (`main/main.npy`), compiled by PXX
into an ESP-IDF application.

A weather-station-style status page: the board starts an access point (`PXX-NILPY`) and serves a page at `http://192.168.4.1/`.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/nilpy-station-s3 --port /dev/ttyACM0
```

The expected serial output is `main/main.expected`.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
