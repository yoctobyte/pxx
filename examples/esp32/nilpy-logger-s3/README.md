# nilpy-logger-s3

**Chip:** ESP32-S3 (Xtensa LX7). **Language:** Nil Python (`main/main.npy`), compiled by PXX
into an ESP-IDF application.

A Wi-Fi data logger in the MicroPython style. With no saved network it starts
the access point `PXX-SETUP` (password `pxx-setup`) and serves a setup form at
`http://192.168.4.1/`; the network you enter is saved to `/config.json` on the
board's flash, in plain text. Once joined it appends uptime, temperature and
free heap to `/log.csv` every 5 seconds and serves them over HTTP. The code is
split across `logstore.npy`, `web.npy` and `logger.npy` next to `main.npy`.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/nilpy-logger-s3 --port /dev/ttyACM0
```

## QEMU

This example needs a board: an ESP32-S3 board, and a phone or laptop to join its Wi-Fi network. Espressif's QEMU has no Wi-Fi, and the project ships no `main/main.expected`: `./build.sh qemu-assert` stops with `main/main.expected: No such file or directory`. Checked on 2026-09-29 with v451 (compiler sha256 `d9b7226769cc`) from the release archive.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
