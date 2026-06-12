# Compile target: ESP32 / embedded

- **Type:** feature
- **Status:** done
- **Owner:** Antigravity / Claude
- **Unblocks:** feature-additional-cpu-targets
- **Opened:** 2026-06-06 (user request; roadmap.md Phase 5)

## Motivation

The embedded milestone has two useful faces:

- **ESP-IDF integration:** use Espressif's supported SDK/toolchain/build flow so
  PXX programs can run on real ESP32 boards and call Wi-Fi, networking, NVS,
  GPIO, timers, FreeRTOS, and other vendor APIs without reimplementing the SDK.
  This is the practical path for hardware already on the shelf, especially
  ESP32-S2/S3 Xtensa boards.
- **Bare-metal profile:** own startup, memory policy, image/link path, UART/GPIO,
  and allocator without depending on ESP-IDF. This remains useful for compiler
  control, tiny firmware, and later RISC-V ESP32-C3-class work.

The key decision is to treat ESP-IDF as an explicit target profile, not as the
compiler's identity. `target esp32-idf` may depend on Espressif tooling;
`target esp32-bare` does not.

## Scope & Staging

Phase 1 focuses on code generation, targeting bare-metal executables for both architectures to prove the code emitters before moving to ESP-IDF integration:

### 1. Xtensa Backend (`esp32-bare-xtensa`)
- First focus target. Build a narrow instruction encoder core (`xtensaenc.inc`) for LX6/LX7 CPUs.
- Target basic operations: register-register operations, loads/stores, basic branches, stack frames, and prologs/epilogs.
- Preserves frame pointers strictly for reliable unwinding and JTAG/GDB debugging support.

### 2. RISC-V Backend (`esp32-bare-riscv32`)
- Included in Phase 1 due to shared backend helper structures and code-generator libraries.
- Build a RISC-V RV32IMC instruction encoder core (`rv32enc.inc`).
- Setup standard stack frames with frame pointer (`s0`/`fp`) preservation.
- Provides a clean, standard platform for emulator-based debugging under upstream QEMU.

### 3. Standalone Memory Management
- Integrate simple static allocator hooks mapping to SRAM boundary configurations.

### 4. Debugging & Symbol Support
- Generate clean ELF symbol tables and map files (`.map`) to ensure high observability during emulator or hardware-level debugging.

## Acceptance

- Bare-metal executables for both Xtensa and RISC-V can be compiled, booting to a minimal state (UART hello and GPIO toggle).
- Preserved frame pointers enable clean GDB stack traces.
- ELF outputs contain correct symbol listings and correspond to output `.map` files.

## Testing strategy

- **Host tests:** validate macro preprocessor, parser, and code generation mappings.
- **Emulated tests:** boot under QEMU (`qemu-system-xtensa` and `qemu-system-riscv32`) to verify register allocation, calling conventions, stack alignment, and branch logic.
- **JTAG / GDB tests:** verify that a debugger can attach and step/unwind correctly using the generated map files and preserved frame pointers.

## Log
- 2026-06-12 — CLOSED as stage 1 complete: both instruction emitters proven
  by execution under qemu-user (identical oracle globals on riscv32 and
  xtensa) and ESP-IDF environment installed. Remaining acceptance items
  split into follow-on tickets so each fits a clean session:
  - feature-elf-rel-writer (.o emission, ELF symbol tables; root of the
    esp32-idf chain),
  - feature-esp32-idf-riscv32 (C3 end-to-end: component, app_main,
    qemu -M esp32c3 — zero ABI work, proves the pipeline),
  - feature-xtensa-windowed-abi (entry/retw/call8 variant; IDF interop
    requirement for S2/S3),
  - feature-esp32-idf-xtensa (QEMU -M esp32s3 + real S2/S3 hardware,
    GDB/JTAG acceptance),
  - feature-esp32-bare-boot (parked bare face: memory map, UART MMIO,
    .map files, static arena).
- 2026-06-12 — ESP-IDF v6.0.1 installed via tools/install_esp32_target.sh
  (fixed: `set -e` aborted on apt-get update failing over an unrelated broken
  repo). Verified: idf.py, xtensa-esp32s2/s3-elf-gcc 15.2.0, Espressif QEMU
  9.2.2 with `-M esp32`/`-M esp32s3` (xtensa) and `-M esp32c3` (riscv32) under
  ~/.espressif/tools (export.sh doesn't PATH qemu-riscv32 — use full path).
  Host pkgs flex/bison/gperf/ccache/dfu-util still pending (sudo; needed for
  idf.py build). Unblocks: system-mode boot slice — target the real ESP32
  memory map (IRAM 0x40080000, UART0 MMIO 0x3FF40000) + image format for a
  UART hello under `qemu-system-xtensa -M esp32`.
- 2026-06-12 — xtensa smoke binary EXECUTED correctly under user-mode
  `qemu-xtensa` (dc232b core covers our core+density+mul32 subset; ESP32 LX6
  itself absent from stock QEMU): runs to the terminal self-loop, globals
  g=45 i=6 acc=45 — same oracle values as riscv32. Found+fixed a latent bug
  in the shared ELF32 writer: `bssBase = dataBase + DataLen` was byte-granular
  so word globals landed misaligned → Xtensa s32i SIGBUS (riscv32 QEMU only
  tolerated it); bssBase now AlignTo 8, i386/arm32 oracles unaffected.
  Debug recipe: `qemu-xtensa -d in_asm -D log BIN` for execution trace
  (gdb-multiarch's xtensa register readout vs qemu is unreliable — pc reads 0;
  memory reads work fine).
- 2026-06-12 — riscv32 smoke binary EXECUTED correctly under user-mode
  `qemu-riscv32` (loads our ET_EXEC ELF32 directly; no board setup needed):
  `-g` gdb stub + gdb-multiarch breakpoint on the terminal self-loop, then
  dump globals. Result g=45, i=6, acc=45 — exact expected values, proving
  loop/branch/call/param/result/global-store codegen end to end. Recipe:
  `qemu-riscv32 -g 1234 BIN` + `gdb-multiarch -ex "target remote :1234"
  -ex "break *<self-loop vaddr>" -ex continue -ex "x/3dw <bss globals>"`.
  Globals start at bssBase+4176 (7 qwords reserved + LINE_BUF 4096 + INTBUF 24).
- 2026-06-12 — Stage-1 code generation working for both targets. Wired
  `ir_codegen_riscv32.inc` + new `ir_codegen_xtensa.inc` into the IR dispatch;
  param spill in prologues (RV32: a0–a7, Call0: a2–a7); bare-metal exit =
  self-loop; `builtinheap` skipped on these targets (no allocator yet).
  Encoder fixes vs. the earlier draft: J imm18 is at insn bits [23:6] (was
  shl 4), RET is LE bytes `80 00 00` (was byte-swapped), CALL0 is relative to
  `align4(PC)+4` and needs 4-aligned proc entries (entries now NOP-padded),
  L32R offsets are one-extended (negative only) so 32-bit literals/addresses
  use a jump-over-literal-then-`l32r rd, $FFFF` island, not a forward L32R.
  All Xtensa encodings cross-checked against llvm-mc (Xtensa target, LLVM 18);
  MULL ($82 sub-op) is ISA-documented but not verifiable with stock llvm-18.
  RV32 smoke binary fully disassembles clean under binutils objdump: prologue,
  spill, literal pools, calls, slt-based comparisons, self-loop. Remaining for
  acceptance: QEMU boot, UART write path, .map files + ELF symbol tables,
  div/mod/shift on Xtensa (needs QUOS/SSL-family or runtime helpers).
  Landmine: PXX `not` is not a bitwise integer op — never write
  `x and (not 3)`; use `(x div 4) * 4`.
- 2026-06-12 — Claimed by Antigravity; transitioned to working. Updated scope to include both Xtensa (primary focus) and RISC-V in Phase 1 due to shared code-emission library structures, prioritizing frame pointer and symbol table support for debugging.
- 2026-06-11 — revised with user after ESP-IDF/FreeRTOS discussion and actual hardware inventory. Do not skip Xtensa for the practical IDF path: user has ESP32-S2/S3 boards. Use Espressif's toolchain/build system when the goal is Wi-Fi/networking/vendor drivers.
- 2026-06-10 — scope decision with user: target the ISA. RISC-V RV32IMC covers forward roadmap; ESP32-C3 reference chip.
- 2026-06-06 — ticket opened from user request.
- 2026-06-12 — host packages verified installed (flex, bison, gperf, ccache,
  dfu-util, cmake, ninja, libusb-1.0-0); `idf.py --version` reports
  ESP-IDF v6.0.1 after export.sh; Espressif qemu-system-riscv32 9.2.2 has the
  `esp32c3` machine. Nothing blocks `idf.py build` for
  feature-esp32-idf-riscv32.
