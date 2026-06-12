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

QEMU smoke:

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

The program then blinks GPIO 2 and parks through `vTaskDelay`, so FreeRTOS
idle continues to run. GPIO 2 is only a simple smoke default; use the board's
actual LED GPIO for hardware demos if needed.
