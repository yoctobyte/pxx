# PXX ESP32-S3 ESP-IDF hello

This is the Xtensa/windowed-ABI companion to `examples/esp32/hello-c3`.
`main/main.pas` is compiled to a relocatable object with
`--target=xtensa --xtensa-abi=windowed`, archived as `main/libpxx_app.a`,
and linked by ESP-IDF as the provider of `app_main`.

Build:

```sh
. ~/esp/esp-idf/export.sh
make compiler/pascal26
cd examples/esp32/hello-s3
./build.sh
```

The link map should show `app_main` coming from `libpxx_app.a(main.o)`.
The Pascal code hand-declares ESP-IDF/ROM externals (`esp_rom_printf`,
`gpio_set_direction`, `gpio_set_level`, `vTaskDelay`) and calls them
directly. No C wrapper is used.

QEMU smoke, one line and headless: `./build.sh qemu` runs
`tools/esp_run.sh --chip esp32s3` on this program with the script's own
compiler, prints the program's output and exits. Any other argument is refused
with a usage line (exit 2). It needs Espressif's QEMU, which ESP-IDF installs
only on request (see
"Running without a board" in [ESP32 / Microcontrollers](../../../docs/targets/esp32.md)).

By hand, after `./build.sh` (it runs until you press Ctrl-A, then X):

```sh
cd build
python -m esptool --chip esp32s3 merge-bin -o /tmp/flash-s3.bin @flash_args --fill-flash-size 2MB
~/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa \
  -M esp32s3 -drive file=/tmp/flash-s3.bin,if=mtd,format=raw \
  -serial mon:stdio -nographic
```

Expected serial lines after the normal ESP-IDF boot banner:

```text
PXX hello from Pascal S3: i=1
PXX hello from Pascal S3: i=2
PXX hello from Pascal S3: i=3
PXX hello from Pascal S3: i=4
PXX hello from Pascal S3: i=5
PXX S3 sum 1..5 = 15
```

Re-checked 2026-09-28 with pin v450 (compiler sha256 `c19cc2d531e4`) under Espressif QEMU, not on a board: `tools/esp_run.sh --chip esp32s3 examples/esp32/hello-s3/main/main.pas` printed exactly these six lines.

The program then blinks GPIO 2 and parks through `vTaskDelay`, so FreeRTOS
idle continues to run. GPIO 2 is only a simple smoke default; use the board's
actual LED GPIO for hardware demos if needed.

Checked on 2026-09-29 with v451 (compiler sha256 `d9b7226769cc`) from the release archive, under Espressif's QEMU, not on a board: `./build.sh qemu` printed the six `PXX hello from Pascal S3` lines, ending `PXX S3 sum 1..5 = 15`, after about 2 minutes.
