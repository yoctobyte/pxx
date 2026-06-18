# ESP32 bare-metal boot profile (no IDF)

- **Type:** feature
- **Status:** DONE 2026-06-18 (esp32c3/riscv32 + esp32s3/xtensa Call0, qemu-validated)
- **Owner:** —
- **Opened:** 2026-06-12 (split from feature-target-esp32; parks the bare face)

## Motivation

The bare-metal face of the ESP32 milestone: own startup, image layout, UART
and allocator with no ESP-IDF dependency. Stage-1 codegen
(done/feature-target-esp32) proved the instruction emitters under qemu-user
with Linux-style ELF; booting a real `-M esp32`/`-M esp32c3` machine (or a
chip from flash) needs the actual SoC contract. Lower priority than the IDF
profile — useful for compiler control, tiny images, and education.

## Scope

- Target the ESP32 memory map instead of `LOAD_ADDR32`: code in IRAM
  (0x4008xxxx on LX6 / per-SoC), data in DRAM; ROM bootloader image format
  (or direct `-kernel` ELF load where Espressif QEMU accepts it).
- Minimal startup: set sp, zero BSS (kernel did both for us under
  qemu-user), jump to main; Xtensa additionally needs vecbase/PS sanity if
  staying Call0.
- UART hello: MMIO stores to UART0 FIFO (0x3FF40000 on ESP32 classic;
  per-SoC address) — gives writeln a real backend on bare metal.
- Static-arena allocator hooks (ties into feature-static-arena-profile).
- `.map` file emission for the bare path (the IDF profile gets maps from the
  IDF linker for free).

## Acceptance

- Bare image boots under Espressif QEMU (`-M esp32c3` first — simpler core)
  and prints over emulated UART; same recipe documented for `-M esp32s3`.
- Frame-pointer-preserved stack walk confirmed in gdb against the bare image.

## Progress log

### 2026-06-18 — esp32c3/riscv32 bare-boot DONE

`--esp-profile=bare` (riscv32) ships. Acceptance for the C3 met:

- **Boots + prints over UART** under `qemu-system-riscv32 -M esp32c3 -kernel`,
  byte-identical to the x86-64 oracle (`make test-esp-bare`,
  `test/test_esp_bare.pas`, harness `tools/esp_run_bare.sh`).
- **Frame-pointer stack walk confirmed** in `riscv32-esp-elf-gdb`: the `s0`
  fp-chain unwinds a deep recursion cleanly to `main` (fp terminates at 0).

Settled load path (the key open question): Espressif qemu accepts a raw `ET_EXEC`
ELF via `-kernel` — it honors the program-header load address and sets `pc` to
the ELF entry. **No flash image / `esptool merge-bin` / second-stage header
needed.** The C3 SRAM is mapped twice (IRAM/DRAM) but qemu models it as one RWX
region, so a single PT_LOAD at `ESP_BARE_IRAM_BASE = 0x40380000` holds
code+data+bss+stack. Startup stub sets `sp = ESP_BARE_STACK_TOP = 0x403C0000`.
UART0 TX FIFO MMIO at `0x60000000`. Static-arena heap + managed AnsiString work
unchanged on bare metal. ESP-gated; `make test` + `make cross-bootstrap` stay
byte-identical. Full write-up in `docs/developer/esp32-support.md`
(§ Bare-metal boot).

Implementation: `EspBareBoot` flag (compiler.pas) → `PXX_ESP_BARE` define
(lexer.inc); ESP base in `writeELF32` (elfwriter.inc); sp-init in the riscv32
entry stub (parser.inc). `.map`/symtab emission for the bare path is not done
(gdb works via stepi + manual fp-walk; the IDF profile already gets maps).

### 2026-06-18 — esp32s3/xtensa bare-boot DONE (same session)

Same image shape, **Call0 ABI only**. `--esp-profile=bare --target=xtensa`
boots under `qemu-system-xtensa -M esp32s3 -kernel`, UART output byte-identical
to the oracle (`make test-esp-bare` runs both chips). Image base
`ESP_BARE_IRAM_BASE_XT = 0x40378000` (S3 shared I/D SRAM org); same stack top
`0x403C0000` and UART `0x60000000`. The entry stub loads `sp = a1` from an
`l32r` literal island before `main`. Windowed ABI is rejected on bare (no
window-exception handlers / vecbase) — Call0 sidesteps register windows
entirely, so managed strings + heap + recursion all run with no vecbase/PS
setup. `-kernel` honors the ELF load address here too (the xtensa qemu warns
about a default `-bios` but loads our kernel). Forward-decl of
`EmitLoadConstXtensa` added in symtab.inc so the parser entry stub can call it.

The whole bare-boot ticket is now complete for the user's two boards
(esp32c3 + esp32s3). `.map`/symtab emission for the bare path remains the one
deferred scope item (not needed for the gdb proof; the IDF profile gets maps).

## Notes

- Espressif QEMU + toolchains installed 2026-06-12 (see
  done/feature-target-esp32 log).
- Keep using qemu-user for fast logic oracles; system mode only proves boot
  + MMIO.
- This qemu gdbstub does not honor breakpoints (`continue` hangs); use `stepi`.
