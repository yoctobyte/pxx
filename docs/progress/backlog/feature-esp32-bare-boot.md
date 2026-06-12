# ESP32 bare-metal boot profile (no IDF)

- **Type:** feature
- **Status:** backlog
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

## Notes

- Espressif QEMU + toolchains installed 2026-06-12 (see
  done/feature-target-esp32 log).
- Keep using qemu-user for fast logic oracles; system mode only proves boot
  + MMIO.
