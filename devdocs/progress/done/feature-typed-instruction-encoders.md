# Typed instruction encoders for codegen

- **Type:** feature
- **Status:** done
- **Owner:** Antigravity
- **Opened:** 2026-06-11 (user request)
- **Closed:** 2026-06-12 (implemented and bootstrap verified)

## Motivation

Backend codegen currently emits raw bytes/words/quadwords directly, with
comments documenting the intended machine instruction. That works, but every
new backend feature repeats operand packing, branch displacement encoding, and
bitfield composition at the call site. The next queued work adds more of that
surface area: cross exceptions, cross float/Variant support, full parameter ABI,
and later targets such as RISC-V / ESP32-class MCUs.

Introduce small typed instruction encoders so new codegen emits through tested
helpers instead of hand-rolled byte math. This is now priority prep before ESP32
work: a clean encoder layer reduces risk for future RISC-V/Xtensa target work
and gives inline asm a better lower layer without deciding PXX-specific asm
syntax yet.

## Scope

- Add a narrow x86-64 encoder core first, factored around forms already emitted
  by the compiler and inline asm:
  - `mov reg, imm`, `mov reg, reg`
  - `mov [rbp+disp], reg`, `mov reg, [rbp+disp]`
  - ALU/cmp/test forms already used by codegen or `asmenc.inc`
  - `call rel32`, `jmp rel32`, `jcc rel32`
  - `syscall`, `ret`, `leave`, `nop`
- Keep helpers small and typed around actual emitted forms. Do not build a full
  assembler or a constant-per-instruction table.
- Add focused encoding tests that assert exact bytes for representative forms
  and boundary cases, especially ModRM/SIB/displacement and branch fixups.
- Start by adopting the helpers in high-churn or newly touched x86-64 codegen
  and in `asmenc.inc` internals where it removes duplicated ModRM logic.
- After the x86-64 pattern is proven, add target-specific encoder files as work
  demands:
  - `a64enc.inc` / `a32enc.inc` for ARM-family fixed-width instruction words.
  - `rv32enc.inc` for ESP32-C3/RISC-V (`LUI`, `ADDI`, `LW/SW`, `JAL/JALR`,
    `BEQ/BNE`, `ECALL`, etc.).
  - Adopt for new codegen first. Convert existing raw emit sites only when already
    touching the surrounding code or when a bug fix proves the helper useful.

## Non-goals

- No flag-day conversion of all existing byte emission.
- No constant-per-instruction scheme. Register fields, displacements, immediates,
  and addressing modes make constants the wrong abstraction for most forms.
- No full text assembler in this ticket. A text parser for inline asm can sit on
  top of the encoder core later, but the encoder is the shared lower layer.
- No user-visible asm syntax changes in this ticket.

## Acceptance

- New or touched x86-64 codegen can express common instruction forms through
  typed encoder helpers instead of raw byte emission at the call site.
- Encoding tests cover the first-pass x86-64 helpers, including branch
  displacement and stack-frame load/store forms.
- Existing fixedpoint/bootstrap checks remain byte-identical for any converted
  call sites.
- Inline raw bytes/words remain centralized and commented inside encoder bodies
  so the encoding remains auditable.

## Notes

- Treat this as a forward-adoption feature, not a refactor project. The value is
  in making upcoming codegen safer and clearer.
- Good trigger point: do this before `feature-target-esp32`, so RV32/Xtensa work
  starts with a tested encoder pattern instead of another layer of hand-packed
  instruction words.

## Log

- 2026-06-12 — Encoder core implemented in commit (pending). Added `x64enc.inc`, tested via `test_x64enc.pas`, and adopted in `symtab.inc` (`EmitLeaveExceptionFrameX64`/`EmitManagedLocalCleanup`) and `asmenc.inc` (`AsmPrefixAndREX`/`AsmModRM`/`AsmEncodeMov`/push/pop).
- 2026-06-12 — Scope revised to x86-64 encoder core first, with ARM/RV32 encoder files following target work.
- 2026-06-11 — Ticket opened.
