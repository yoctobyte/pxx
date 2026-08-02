# PXX ESP32-S2 ESP-IDF hello

The Xtensa sibling of `hello-s3`, for the **ESP32-S2**. Same source shape, same
`--target=xtensa --xtensa-abi=windowed` compile; only the IDF target differs.

**The S2 cannot be emulated.** Espressif's QEMU fork ships machines for `esp32`,
`esp32s3` and `esp32c3` — there is no `esp32s2`. So unlike every other project
here, this one is verified by *building* headlessly and *running* on a board:

```sh
. ~/esp/esp-idf/export.sh
make compiler/pascal26
cd examples/esp32/hello-s2 && ./build.sh          # links, prints the map check
```

and then, with a board on USB:

```sh
tools/esp_flash.sh --chip esp32s2 test/test_esp_hw_validation.pas
```

which compiles, flashes, reads the serial output back and diffs it against the
same program run on x86-64. See
`devdocs/progress/*/feature-esp-hardware-flash-validation.md` for the full
procedure and what to check.

This project also doubles as `tools/esp_flash.sh`'s S2 harness: it links whatever
`.pas` the script is given, which is why its component `REQUIRES esp_timer lwip
esp_netif` even though the hello itself uses none of them.
