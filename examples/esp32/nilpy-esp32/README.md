# nilpy-esp32

**Chip:** ESP32 (the classic part) (Xtensa LX6). **Language:** Nil Python (`main/main.npy`), compiled by PXX
into an ESP-IDF application.

A small Python program (a class, a list of instances, a loop, `print`) compiled to machine code. The same source as `nilpy-c3` and `nilpy-s3`.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/nilpy-esp32 --port /dev/ttyACM0
```

The expected serial output is `main/main.expected`.

**Board output, not re-measured on v450.** Last measured 2026-09-28 on an ESP32-D0WD-V3 with
compiler `b2b325036c3b` (pin v448): the board output matched `main.expected`,
4 lines (`examples/esp32/nilpy-hw-esp32/README.md`, LOGBOOK 2026-09-28).

## Run under QEMU

No board needed. From this directory in the release archive, with Espressif's QEMU installed (see [ESP32](../../../docs/targets/esp32.md)):

```sh
. ~/esp/esp-idf/export.sh
./build.sh qemu-assert
```

Checked on 2026-09-29 with v451 (compiler sha256 `d9b7226769cc`) from the release archive, under Espressif's QEMU, not on a board: `./build.sh qemu-assert` ended with `OK   nilpy-esp32 -- a static Python application runs on the esp32, output == main/main.expected, one boot` after about 4 minutes.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
