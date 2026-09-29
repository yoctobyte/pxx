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

## Run under QEMU

No board needed. From this directory in the release archive, with Espressif's QEMU installed (see [ESP32](../../../docs/targets/esp32.md)):

```sh
. ~/esp/esp-idf/export.sh
./build.sh qemu-assert
```

Checked on 2026-09-29 with v451 (compiler sha256 `d9b7226769cc`) from the release archive, under Espressif's QEMU, not on a board: `./build.sh qemu-assert` ended with `OK   isrctx-c3 qemu acceptance -- task ctx=0, ISR ctx=1 (asymmetry witnessed)` after about 1 minutes.

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
