# Compile target: ESP32 / embedded

- **Type:** feature
- **Status:** working
- **Owner:** Antigravity
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
