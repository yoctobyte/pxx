# pwm-s3

**Chip:** ESP32-S3 (Xtensa LX7). **Language:** Pascal (`main/main.pas`), compiled by PXX
into an ESP-IDF application.

PWM on a pin (`esppwm`), measured by the same chip reading the pin back. Nothing wired.

Build only, nothing is written to a board:

```sh
. ~/esp/esp-idf/export.sh
./build.sh
```

Build, flash and check the board's output, from the repository root:

```sh
tools/esp_flash.sh --project examples/esp32/pwm-s3 --port /dev/ttyACM0
```

See [ESP32 / Microcontrollers](../../../docs/targets/esp32.md) for how far each chip is proven.
