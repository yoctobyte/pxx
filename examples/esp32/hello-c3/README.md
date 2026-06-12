# PXX → ESP-IDF hello (ESP32-C3)

Minimal proof that a PXX-compiled Pascal program integrates with ESP-IDF:
`main/main.pas` is compiled to a relocatable object (`--target=riscv32`,
ET_REL `.o`), wrapped in a static archive, and linked by the normal
`idf.py build` as the provider of `app_main`. ESP-IDF owns boot, FreeRTOS,
and the vendor APIs; the Pascal side calls `esp_rom_printf` and `vTaskDelay`
through plain `external` declarations.

## Build

```bash
. ~/esp/esp-idf/export.sh     # idf.py + toolchains on PATH
./build.sh                    # compiles main.pas -> main.o -> libpxx_app.a,
                              # then idf.py set-target esp32c3 + build
```

`build/pxx_hello_c3.map` shows `app_main` provided by
`main/libpxx_app.a(main.o)`.

## Run under Espressif QEMU

Interactive: `./build.sh qemu` (uses `idf.py qemu monitor`).

Headless (export.sh does not PATH qemu-system-riscv32 — use the full path):

```bash
cd build
python -m esptool --chip esp32c3 merge-bin -o /tmp/flash.bin @flash_args --fill-flash-size 2MB
~/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 \
  -M esp32c3 -drive file=/tmp/flash.bin,if=mtd,format=raw \
  -nographic -serial mon:stdio -monitor none
```

Expected serial output after the IDF boot banner:

```
PXX hello from Pascal: i=1
PXX hello from Pascal: i=2
PXX hello from Pascal: i=3
PXX hello from Pascal: i=4
PXX hello from Pascal: i=5
PXX sum 1..5 = 15
```

The program then parks in a `vTaskDelay` loop (PXX's `app_main` has no
returning epilogue yet), so the FreeRTOS idle task keeps the watchdog fed.

## Notes

- Externals are hand-declared (`procedure esp_rom_printf(fmt: string;
  v: Integer); external;`). String-literal arguments are auto-marshalled to
  `const char*` (the 8-byte PXX length prefix is skipped at the call site).
- RV32 varargs pass in registers like normal args; stick to 32-bit values
  with `esp_rom_printf`.
- Real-hardware flashing should work with `idf.py flash monitor` but is
  untested (no C3 board on hand); S2/S3 boards need the Xtensa windowed-ABI
  ticket first.
