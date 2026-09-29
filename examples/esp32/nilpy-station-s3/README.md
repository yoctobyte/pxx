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

## QEMU

This example needs a board: an ESP32-S3 board, and a phone or laptop to join its Wi-Fi network. Espressif's QEMU has no Wi-Fi: under `./build.sh qemu-assert` the chip boots and the program prints nothing, so the check reports FAIL. Checked on 2026-09-29 with v451 (compiler sha256 `d9b7226769cc`) from the release archive.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
