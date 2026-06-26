# ESP-IDF integration: riscv32 (ESP32-C3) end-to-end

- **Type:** feature
- **Status:** done
- **Owner:** claude
- **Blocked-by:** feature-elf-rel-writer
- **Unblocks:** feature-esp32-idf-xtensa
- **Opened:** 2026-06-12 (esp32-idf integration plan)

## Motivation

First full PXX→IDF link-and-boot proof, on the architecture with **zero ABI
work**: our RISC-V codegen already follows the standard ILP32 convention
(args a0–a7, result a0, fp s0), which is exactly what IDF's
riscv32-esp-elf-gcc world expects. Proves the whole pipeline — .o emit,
component registration, IDF link, boot under Espressif QEMU — before the
Xtensa ABI variant exists.

## Scope

- Install the C3 toolchain: `~/esp/esp-idf/install.sh esp32c3` (Xtensa-only
  s2,s3 were installed 2026-06-12; tools/install_esp32_target.sh
  ESP_IDF_TARGETS=esp32c3 does it).
- Template IDF project under `examples/esp32/` (or similar):
  `main/CMakeLists.txt` registering the PXX-built object via
  `add_prebuilt_library` / `target_link_libraries`, plus a build rule (or a
  small wrapper script) invoking `./compiler/pascal26 --target=riscv32
  --emit-obj main.pas main.o`.
- Pascal `app_main` calling a couple of hand-declared IDF externals —
  `esp_rom_printf` (works before full console init) and `vTaskDelay` are
  enough.
- Run under Espressif QEMU: `idf.py qemu monitor` or direct
  `qemu-system-riscv32 -M esp32c3` (full path:
  `~/.espressif/tools/qemu-riscv32/*/qemu/bin/` — export.sh does not PATH it).

## Non-goals

- No automatic C header import (hand `external` decls only; see
  feature-c-header-import-complex for the real thing).
- No Wi-Fi/networking. printf + delay loop is the acceptance bar.
- No real C3 hardware (user boards are S2/S3).

## Acceptance

- `idf.py build` produces a flashable image whose `app_main` is PXX-compiled
  Pascal (verify symbol in map file — IDF emits the .map for free).
- Boots under `qemu-system-riscv32 -M esp32c3`; serial shows output printed
  from a Pascal loop via `esp_rom_printf`.
- Recipe documented in the example dir README (env: `. ~/esp/esp-idf/export.sh`).

## Notes

- ESP-IDF v6.0.1 at ~/esp/esp-idf; host packages installed.
- Calling convention trap to watch: IDF varargs (`esp_rom_printf`) on RV32
  passes varargs in regs like normal args — our caller already does that, but
  64-bit varargs would need register-pair alignment; stick to 32-bit args.

## Log
- 2026-06-12 — DONE (commit c372647). examples/esp32/hello-c3: Pascal
  app_main compiled --target=riscv32 to .o, ar-wrapped, registered via
  add_prebuilt_library in the main component (+ `-u app_main`); idf.py build
  links it (map shows app_main = libpxx_app.a(main.o) at 0x4200b06c). Boots
  under Espressif qemu-system-riscv32 -M esp32c3 (merge-bin flash image):
  serial prints "PXX hello from Pascal: i=1..5" and "PXX sum 1..5 = 15" via
  esp_rom_printf, then parks in a vTaskDelay loop — no WDT, no crash.
  Acceptance met: build + map proof + QEMU serial + README recipe.
  Required compiler work: (1) esp32 external calls auto-marshal string
  literals to const char* (+8 past the length prefix); (2) lexer fix —
  adjacent 'str'#nn segments now lex as ONE literal (was per-segment tokens;
  broke argument lists). The never-returning app_main is worked around in
  Pascal (terminal `while True do vTaskDelay(1000)`); a returning epilogue
  remains future work if ever needed.
