# isrctx-c3

**Chip:** ESP32-C3 (RISC-V, RV32IMC). **Language:** Pascal (`main/main.pas`), compiled by PXX
into an ESP-IDF application.

Checks that a Pascal routine called from an `esp_timer` interrupt runs in interrupt context, and a task routine in task context. Nothing wired.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/isrctx-c3 --port /dev/ttyACM0
```

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
