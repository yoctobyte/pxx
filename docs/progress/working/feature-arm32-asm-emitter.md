# ARM32 text-assembler (`EmitAsmArm32`) for cleaner ARM32 codegen

- **Type:** feature
- **Status:** working
- **Owner:** Antigravity
- **Depends-on:** feature-array-of-const (DONE), feature-asm-text-emitter
  (shared `asmtext.inc` helpers, DONE); recommended **after**
  feature-aarch64-asm-emitter (reuse its fixed-width front-end + new enc layer)
- **Opened:** 2026-06-14

## Motivation

`ir_codegen_arm32.inc` is **1904 lines** of raw word emission. Same readability
/ maintenance win as the other target emitters; last of the three.

## New vs the x86/xtensa precedent

**No typed encoder layer exists** for ARM32 (like AArch64). Grow a thin
`compiler/arm32enc.inc` (typed `EncodeArm32*` over the byte sink) under
`EmitAsmArm32`, or share the front-end built for `EmitAsmA64`. A32 is also
fixed-width 32-bit, so the AArch64 emitter's structure largely carries over —
the encoding fields differ.

## Operand model

`mnem dst, src, …`. Registers `r0..r15` (`sp`=r13, `lr`=r14, `pc`=r15).
`Loads/stores ldr r3, [r2, #8]`. Data-processing immediates are the ARM32
quirk: **8-bit value rotated by an even amount** (imm8 + rot4), not a flat
imm12 — the encoder must find a valid rotation or reject. Markers `%` / `.label:`
/ `@data` / `@glob` as elsewhere.

## Scope (incremental — mix freely)

1. Cover what converted blocks use first: `mov mvn add sub and orr eor cmp`
   (imm8-rot + register forms), `ldr str ldrb strb` (base+imm), `bx lr`,
   branches `b`/`bl` (rel24 `<<2`) and condition-coded `beq`/`bne`/… (the
   `[31:28]` condition field). Grow on demand.
2. Labels + branch offset resolution back+forward (rel24, word-scaled).
3. **Convert ≥1 real branch/label-bearing block.** Leave dynamic blocks on
   inline word emission.

## Landmines

- **4-byte alignment is mandatory** — ARM32 code must stay word-aligned; any
  unguarded path that emits an odd byte count misaligns every following
  instruction. The emitter must never produce a non-multiple-of-4 sequence;
  if mixing with byte-level paths, assert alignment at block boundaries.
  [[project_arm32_alignment_landmine]].
- **Condition field:** every A32 instruction carries `cond` at `[31:28]`;
  `beq`/`bne`/etc. are `b` with a cond — encode it from the mnemonic suffix, not
  a separate table.
- **imm8-rotate operand:** reject data-proc immediates with no valid
  8-bit-rotated encoding loudly (don't silently truncate).
- **PXX self-host:** `AsmTextCharAt`, no `var AnsiString` reassign, module-global
  scratch tables. [[project_pxx_and_not_shortcircuit]].
- llvm-mc as the encoding oracle.

## Acceptance

- `EmitAsmArm32` (+ single-line overload) with the rules above.
- ≥1 `ir_codegen_arm32.inc` block converted; correct under the arm32 run path
  (`make test-arm32` / QEMU); alignment verified (objdump).
- `test/test_asm_emit_arm32.pas` against known-good bytes.
- Cross fixedpoint where one exists stays byte-identical / consistent.

## Deferred

Thumb/Thumb-2, `ldr rd,=imm` literal-pool sugar, shifted-register operands
beyond what blocks need, the full `ir_codegen_arm32.inc` conversion.

## Log

- 2026-06-14 — opened. Third / last of the remaining target emitters. Fixed-width
  like AArch64; the imm8-rotate operand and the mandatory 4-byte alignment are
  the ARM32-specific traps.
- 2026-06-14 — claimed by Antigravity; starting implementation.
