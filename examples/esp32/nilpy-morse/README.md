# nilpy-morse

**Language:** Nil Python (`morse_beacon.npy`), MicroPython style. **Chips:** builds for the ESP32-C3 and ESP32-S3.

A morse beacon. It keys messages out over I2C to a PCF8574 I/O expander at 0x20 (bit 0 = LED, bit 1 = buzzer), using `machine.I2C` on SCL GPIO9 and SDA GPIO8. It has a 41-entry morse dict, a `key = value` config parser, a small message queue, and uptime, duty-cycle and I2C error stats printed with `print`.

It was written on 2026-10-15 as the NilPy sample for the bytecode census in [bytecode-vm-for-mcus.md](../../../devdocs/dev/bytecode-vm-for-mcus.md), next to two Pascal apps (the remote thermostat and museum_landkaart). It is a source file only, with no ESP-IDF project around it yet.

**Status: built, never run.** It has not run on a board or under QEMU.

It builds as an object for each chip. From the repository root:

```sh
./compiler/pascal26 --target=esp32c3 --platform=esp --no-signals \
  -Fu$PWD/lib/rtl -Fu$PWD/lib/rtl/platform/esp \
  examples/esp32/nilpy-morse/morse_beacon.npy /tmp/morse_c3.o

./compiler/pascal26 --target=esp32s3 --platform=esp --no-signals --xtensa-long-calls \
  -Fu$PWD/lib/rtl -Fu$PWD/lib/rtl/platform/esp \
  examples/esp32/nilpy-morse/morse_beacon.npy /tmp/morse_s3.o
```

Measured on 2026-10-15 at master `3f4c262efb`, without `--dce`:

| Chip | Code | Data | BSS |
|---|---|---|---|
| ESP32-C3 | 845,352 B | 153,904 B | 81,072 B |
| ESP32-S3 | 2,030,257 B | 153,904 B | 81,140 B |

The S3 build needs `--xtensa-long-calls`, because the image is larger than a CALL0/CALL8 instruction can reach (±512 KiB). The other NilPy examples need it too.

To run it on a board, it needs a project like [nilpy-hw-c3](../nilpy-hw-c3), which provides the IDF wrapper, the large app partition and `esp_flash.sh`.
