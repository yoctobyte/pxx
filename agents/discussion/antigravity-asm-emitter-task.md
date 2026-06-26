# Task brief for Antigravity — `EmitAsmRv32` text assembler

You are unbanned for ONE scoped task. Read this whole brief before touching
anything. Read `agents/AGENTS.md` (access restrictions + navigation) first.

## Hard guardrails (the ban was about these — do not break them)

- **One ticket only:** `devdocs/progress/backlog/feature-rv32-asm-emitter.md`.
  Claim it (set Owner + Status, add a Log line), then work only it.
- **Do not roam.** Touch only: `compiler/asmtext_rv32.inc` (new),
  `compiler/asmtext.inc` (only to share existing `AsmText*` helpers), the one
  `compiler/ir_codegen_riscv32.inc` block you convert, and a new
  `test/test_asm_emit_rv32.pas`. Nothing else. No other backend, no other ticket.
- **Do not read the whole tree file-by-file.** Use `agents/codemap/symbols.md`
  (per-file symbol index) to locate things. Grep targeted, not `*`.
- **Stop at the acceptance gate** (below). Don't expand scope, don't "improve"
  unrelated code. If blocked, write the blocker in the ticket Log and stop —
  don't loop.
- If you find yourself examining files line-by-line or re-reading the same file,
  STOP and re-read this brief.

## What to build

A RISC-V (RV32) text assembler `EmitAsmRv32(const items: array of const)`, the
same shape as the **done** Xtensa one. This is a front-end over the EXISTING
typed encoders — you are NOT writing new instruction encoders.

## Copy this precedent (almost verbatim)

`compiler/asmtext_xtensa.inc` = `EmitAsmXtensa`. It is your template. It:
- parses one instruction per array-of-const string,
- binds `%` holes from the following `vtInteger` elements,
- resolves `.name:` labels and branch/jump offsets (back + forward),
- encodes through the typed per-target layer + byte sink,
- reuses the shared `AsmText*` helpers in `compiler/asmtext.inc`
  (`AsmTextCharAt`, slice, parse-int, hole-binding loop).

Your lower layer already exists: `compiler/rv32enc.inc` — typed `rv32_add`,
`rv32_addi`, `rv32_lw`, `rv32_jal`, `EmitRType/IType/SType/BType/UType/JType`,
`EncodeRISCVJAL`, etc. Call these; do not reimplement them.

## Operand model (RV32, fixed-width 32-bit, no ModRM)

- `mnem rd, rs1, rs2` or `mnem rd, rs1, imm`.
- Registers `x0..x31` + ABI aliases (`zero ra sp gp tp t0.. a0.. s0..`).
- Loads/stores use `imm(reg)`: `lw a0, 8(sp)` (NOT bracketed `[..]`).
- Markers: `%` = value hole (imm/offset/branch, range-checked per format);
  `.name:` = label; `@data`/`@glob` = reloc (the `auipc`+lo12 split — the one
  multi-instruction expansion; handle explicitly, see the x86 `@data` hole).

## Scope (start small, grow on demand)

Cover only what your converted block uses first. Likely: `add sub and or xor`,
`addi andi ori xori slli`, `lui auipc`, `lw lh lb lbu lhu` / `sw sh sb`,
`jal jalr`, branches `beq bne blt bge bltu bgeu`, `ecall`, `ret`/`nop` pseudo.
Then convert **one** real branch/label-bearing block in
`ir_codegen_riscv32.inc`. Leave everything else on the typed `rv32_*` calls.

## PXX self-host landmines (the compiler compiles itself — these WILL bite)

- **No short-circuit `and`/`or`**, and indexing an EMPTY AnsiString derefs nil →
  segfault. Route every conditional char read through `AsmTextCharAt` (returns
  #0 out of range). Never write `(Length(s)>0) and (s[i]=..)`.
- **Never reassign a `var AnsiString` parameter** (frozen-inline overflow) —
  return the value instead.
- **No `Copy`** — use the slice helper in `asmtext.inc`.
- Keep scratch tables (labels, fixups) **module-global**, not local
  `array of AnsiString` (local managed arrays are a self-host landmine).
- Immediate ranges: I/S = 12-bit signed, U = 20-bit. Reject out-of-range loudly.

## Acceptance gate (stop here, report, do not exceed)

1. `EmitAsmRv32` exists with the register/`%`/label/reloc rules + a single-line
   overload.
2. At least one `ir_codegen_riscv32.inc` block (a branch/label one) converted;
   output correct under the riscv32 run path (`make test-riscv32` / QEMU).
3. `test/test_asm_emit_rv32.pas` checks imm/offset/branch/label encodings
   against known-good bytes. **Use llvm-mc as the encoding oracle** (it was the
   oracle for xtensa). Quote the llvm-mc command + expected bytes in the test.
4. `make bootstrap` byte-identical; `make test` green; the riscv32 fixedpoint
   (where one exists) stays consistent.

When all four pass: move the ticket to `done/` with the commit hash in its Log,
update `BOARD.md` via `tools/progress.sh board-md`, run `tools/progress.sh check`.
Then STOP. Do not pick up another emitter unless explicitly told.

## Why you, why this one

It's the cleanest, most bounded emitter: the typed encoder layer already exists
(unlike aarch64/arm32), the precedent is near-verbatim, the backend is the
smallest (432 lines), and the byte-identity gate is objective. Land this clean
and the aarch64/arm32 emitters become candidates. Claude is taking
`EmitAsm386` in parallel (shares the x86 ModRM core + feeds the i386 self-host
arc), so stay off i386.
