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

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
