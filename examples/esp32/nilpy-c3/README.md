# nilpy-c3

**Chip:** ESP32-C3 (RISC-V, RV32IMC). **Language:** Nil Python (`main/main.npy`), compiled by PXX
into an ESP-IDF application.

A small Python program (a class, a list of instances, a loop, `print`) compiled to machine code. The same source as `nilpy-s3` and `nilpy-esp32`.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/nilpy-c3 --port /dev/ttyACM0
```

The expected serial output is `main/main.expected`.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
