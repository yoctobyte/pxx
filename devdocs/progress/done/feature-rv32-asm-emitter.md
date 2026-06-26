# RISC-V (RV32) text-assembler (`EmitAsmRv32`) for cleaner riscv32 codegen

- **Type:** feature
- **Status:** done
- **Owner:** Antigravity
- **Depends-on:** feature-array-of-const (DONE), feature-asm-text-emitter
  (shared `asmtext.inc` helpers + xtensa precedent, DONE)
- **Opened:** 2026-06-14

## Motivation

`ir_codegen_riscv32.inc` (432 lines) emits RV32 through hand calls to the typed
`rv32_*` encoders. Same readability/maintenance win as the other targets, and
RISC-V is the roadmap endgame (bare-metal RISC-V; also the ESP32-C3 path,
[[project_esp32_stage1]]). Smallest backend, so a low-risk conversion.

## Cheapest of the cross emitters — typed layer already exists

Unlike aarch64/arm32 (no encoder layer), **`compiler/rv32enc.inc` is already a
full typed `rv32_*` / `EmitRType`/`IType`/`SType`/`BType`/`UType`/`JType` layer**
— exactly the xtensa situation (`xtensaenc.inc`). So `EmitAsmRv32` is the same
job as `EmitAsmXtensa`: a text front-end over the existing typed encoders, no new
encoding machinery. Mirror `compiler/asmtext_xtensa.inc`.

## Operand model (clean, fixed-width 32-bit, no ModRM)

`mnem rd, rs1, rs2` / `mnem rd, rs1, imm`. Registers `x0..x31` + ABI aliases
(`zero ra sp gp tp t0.. a0.. s0..`). Loads/stores base+imm `lw a0, 8(sp)`
(RISC-V `imm(reg)` form, not bracketed). Markers `%` value hole (imm/offset/
branch, range-checked per format), `.name:` label, `@data`/`@glob` reloc
(`auipc`+`addi`/`lw` pair — call out as the one multi-instruction case).

## Scope (incremental — mix freely)

1. Cover what converted blocks use first: `add sub and or xor sll srl sra`
   (R) + `addi andi ori xori slli` (I), `lui auipc`, `lw lh lb lbu lhu`/`sw sh
   sb`, `jal jalr`, branches `beq bne blt bge bltu bgeu`, `ecall`, `nop`/`ret`
   pseudo. Grow on demand.
2. Labels + branch/jump offset resolution back+forward (B-type ±4 KB, J-type
   ±1 MB; mind the scrambled immediate bit layout the `Emit*Type` already
   handle — pass the byte offset, let the encoder scramble).
3. **Convert ≥1 real branch/label-bearing block.** Leave dynamic blocks on the
   typed `rv32_*` calls.

## Landmines

- **PXX self-host:** `AsmTextCharAt` (no short-circuit / empty-AnsiString
  deref), never reassign a `var AnsiString` param, module-global scratch tables.
  [[project_pxx_and_not_shortcircuit]] / [[project_pxx_array_of_const_selfhost]].
- **Immediate ranges:** I/S = 12-bit signed, U = 20-bit; reject out-of-range
  loudly. The `@data`/`@glob` `auipc`+lo12 split is the only multi-instruction
  expansion — handle it explicitly like the x86 `@data` hole.
- llvm-mc as the encoding oracle (proven on xtensa).

## Acceptance

- `EmitAsmRv32` (+ single-line overload) with register/`%`/label/reloc rules.
- ≥1 `ir_codegen_riscv32.inc` block converted; correct under the riscv32 run
  path (`make test-riscv32` / QEMU / ESP32-C3 where applicable).
- `test/test_asm_emit_rv32.pas` against known-good bytes (imm/offset/branch).
- Cross fixedpoint where one exists stays byte-identical / consistent.

## Deferred

Compressed (C) 16-bit encodings, float (F/D) instructions beyond block needs,
the full `ir_codegen_riscv32.inc` conversion.

## Log

- 2026-06-14 — opened. Typed `rv32_*` layer already exists (`rv32enc.inc`), so
  this is the xtensa-shape text front-end — the cheapest cross emitter. Roadmap
  endgame target (bare-metal RISC-V / ESP32-C3).
- 2026-06-14 — claimed by Antigravity; starting implementation.
- 2026-06-14 — completed implementation in commit 8abad40. Tests passed and bootstrap is byte-identical.
