# AArch64 text-assembler (`EmitAsmA64`) for cleaner ARM64 codegen

- **Type:** feature
- **Status:** done
- **Owner:** Antigravity
- **Depends-on:** feature-array-of-const (DONE), feature-asm-text-emitter
  (shared `asmtext.inc` helpers + x86-64 precedent, DONE); recommended **after**
  feature-i386-asm-emitter (settles the shared front-end shape)
- **Opened:** 2026-06-14

## Motivation

`ir_codegen_aarch64.inc` is **2140 lines** of raw word emission. Same readability
/ maintenance argument as the x86 and xtensa emitters: write blocks as assembly
text, encode once, get correct branch-offset resolution for free.

## New vs the x86/xtensa precedent

**No typed encoder layer exists** for AArch64 — unlike x64 (`x64enc.inc`), rv32
(`rv32enc.inc`), xtensa (`xtensaenc.inc`), the aarch64 backend emits 32-bit
words inline. So this ticket grows the encoders too: either a thin new
`compiler/a64enc.inc` (the xtensa shape — typed `EncodeA64*` over the byte sink)
that `EmitAsmA64` sits on top of, or encode functions inside the text assembler.
Prefer the thin typed layer — it doubles as the seed for future inline asm.

**Upside:** AArch64 is fixed-width 32-bit, no ModRM/SIB/REX, flat register file.
The operand model is simpler than x86 once the encoders exist.

## Operand model

`mnem dst, src, …` comma-separated. Registers `x0..x30`/`sp`/`xzr` (64-bit),
`w0..w30`/`wzr` (32-bit). Loads/stores take base + scaled immediate, **not**
bracketed-flat memory like x86: `ldr x3, [x2, #8]`. Markers: `%` value hole
(imm/offset/branch, range-checked per instruction), `.name:` label, `@data`/
`@glob` reloc.

## Scope (incremental — mix freely)

1. Cover what converted blocks use first: `mov movz movk add sub and orr eor`,
   `ldr str ldrb strb ldrh strh` (base+imm), `ret nop`, branches `b b.cond
   cbz cbnz` + the comparison/`cset` set. Grow on demand.
2. Labels + branch offset resolution back+forward, honouring ranges
   (`b` ±128 MB, `b.cond`/`cbz` ±1 MB) and word-scaled (`>>2`) imm fields.
3. **Convert ≥1 real branch/label-bearing block** (e.g. a `EmitSetccA64`-style
   comparison or a loop). Leave heavily-dynamic blocks on inline word emission.

## Landmines

- **PXX self-host:** reuse `AsmTextCharAt` (no short-circuit / empty-AnsiString
  deref), never reassign a `var AnsiString` param, keep scratch tables
  module-global. [[project_pxx_and_not_shortcircuit]].
- **AArch64 immediate encodings are the trap:** `add`/`sub` shifted imm12,
  `and`/`orr`/`eor` logical-**bitmask** immediates (N:immr:imms), `movz`/`movk`
  16-bit shifted halves. Range/encode-check per instruction; reject unencodable
  immediates loudly.
- Use llvm-mc as the encoding oracle (the proven approach from xtensa /
  [[project_esp32_stage1]]).

## Acceptance

- `EmitAsmA64` (+ single-line overload) with register/`%`/label/reloc rules.
- ≥1 `ir_codegen_aarch64.inc` block converted; correct under the aarch64 run
  path (`make test-aarch64` / QEMU).
- `test/test_asm_emit_a64.pas` against known-good bytes (imm/offset/branch).
- Cross fixedpoint where one exists stays byte-identical / consistent.

## Deferred

## Log

- 2026-06-14 — opened. Second of the three remaining target emitters. Unlike
  x86/xtensa, no typed encoder layer exists yet → grow a thin `a64enc.inc`
  first. Fixed-width ISA, simpler operands; the imm-encoding rules are the work.
- 2026-06-14 — claimed by Antigravity; starting implementation.
- 2026-06-14 — completed implementation, fixed bootstrap parser issue with xor expression parsing, verified under stage 2/3 bootstrap byte-identity and complete test suite (commit f0db05ec086662fee60bd4652919fa7ed4d0b88d).
