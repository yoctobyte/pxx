# Inline assembly support for other architectures (i386, aarch64, arm32)

- **Type:** feature — Track A
- **Status:** working
- **Owner:** Track A agent
- **Opened:** 2026-06-21
- **Relation:** Extends inline assembly to i386, aarch64, and arm32 targets — and, per the 2026-06-30 correction below, riscv32 and xtensa too, for full coverage under the umbrella [[feature-assembler-first-class-citizen]].

## Correction (2026-06-30 — read before starting)

The "Implementation Steps" below originally assumed ARM/i386 instruction
encoders need to be **written from scratch**. They don't — audited the same
day while filing [[feature-asm-structured-ir-library]]: `compiler/
asmtext_386.inc`, `asmtext_a64.inc`, `asmtext_arm32.inc`, `asmtext_rv32.inc`,
and `asmtext_xtensa.inc` **already exist**, each a working label-aware,
relocation-aware (`@glob`/`@data`) text-to-binary instruction assembler for
its target, already used internally by `ir_codegen386.inc` /
`ir_codegen_aarch64.inc` / `ir_codegen_arm32.inc` /
`ir_codegen_riscv32.inc` / `ir_codegen_xtensa.inc`. Do **not** write a new
ARM/i386 syntax parser+encoder per Steps 1-2 below — that work is done.

The real remaining work for this ticket is the same shape as x86-64's (see
[[feature-asm-structured-ir-library]]): make `compiler/asmenc.inc`'s
*parser* (the thing that reads a Pascal `asm...end` block and resolves
identifiers) target-dispatch to the already-existing `EmitAsm386`/
`EmitAsmA64`/`EmitAsmArm32`/`EmitAsmRv32`/`EmitAsmXtensa` engine instead of
raising the current "x86-64 only" error. Land x86-64's wiring first
([[feature-asm-structured-ir-library]]) and copy the pattern per target —
the local/global identifier-resolution glue is target-agnostic; only the
register-name table and a handful of target-specific operand quirks differ.

Riscv32 and xtensa are added to this ticket's scope (not split out) since the
underlying work — wire the parser to an existing engine — is identical in
shape; no reason to track them separately from i386/aarch64/arm32.

## Goal

Wire inline `asm`/`assembler` blocks to the existing per-target text-
assembler engines for: **i386, aarch64, arm32, riscv32, xtensa** (x86-64
already works via [[feature-asm-structured-ir-library]]'s baseline). Register
name tables per target:
- i386: `eax`..`edi`, `esp`, `ebp` (32-bit subset of the x86-64 set).
- aarch64: `x0`..`x30`, `w0`..`w30`, `sp`, `lr`, `pc`.
- arm32: `r0`..`r15`.
- riscv32: `a0`..`a7`, `t0`..`t6`, `s0`..`s11`, `ra`, `sp`, `gp`, `tp`
  (see `reg_*` constants already defined in `compiler/rv32enc.inc`).
- xtensa: `a0`..`a15`, `sp` = `a1` (per `asmtext_xtensa.inc`'s documented
  operand model — Call0 ABI).

## Implementation Steps (revised)

1. Replace the architecture filter check in `AsmParseBody`
   (`compiler/asmenc.inc`) — instead of erroring on non-x86-64 targets,
   dispatch to the target's existing `EmitAsmXxx` engine via the runtime
   instruction-line builder from [[feature-asm-structured-ir-library]].
2. Add each target's register-name table to the identifier-resolution layer
   (above); reuse the existing local-frame-slot and global-symbol resolution
   logic, which is target-agnostic.
3. Target-specific syscall convention for inline asm (e.g. i386 `int 0x80`,
   riscv32 `ecall` with `a7`=syscall number, aarch64/arm32 `svc`) — confirm
   each against what `ir_codegen_<target>.inc` already does for normal
   syscalls, don't invent a new convention.
4. Write target-specific test cases under `test/` verifying instruction
   translation and local/global variable frame-reference resolution, per
   target.

## Log
- 2026-06-21 — Opened.
- 2026-06-30 — Corrected: the assumed-missing ARM/i386 encoders already
  exist (`asmtext_*.inc` family); rescoped from "build encoders" to "wire
  parser to existing engines," and broadened to include riscv32 + xtensa.
- 2026-07-03 — riscv32 leg LANDED. Architecture differs from x86-64's
  parse-time byte encoding on purpose: the cross engines (EmitAsmRv32 et al)
  emit at CodeLen, where label fixups and EmitGlobRef/EmitDataRef relocations
  are natively correct — so the parser captures the block as resolved TEXT
  lines (AsmParseBodyTextRv32 in asmenc.inc: locals/params -> `off(s0)`,
  `la reg,<global>` -> `la reg,@glob` + hole; explicit per-line hole COUNT
  stored, since @glob consumes a hole without a `%`) into InlineAsmLine[],
  and ir_codegen_riscv32.inc's new IR_ASM case replays them through the
  refactored block API (AsmRv32BlockBegin / AsmRv32ProcessLine /
  AsmRv32BlockResolve — extracted from EmitAsmRv32, byte-identical
  restructure). No AsmBytes-offset rebasing needed. Non-wired targets keep a
  clear parse error. Test: test/test_asm_rv32.pas (locals/params, label
  loop, la/@glob global) wired into `make test-riscv32`, green under qemu.
  Remaining scope after this entry: xtensa only (last/optional).
- 2026-07-03 — aarch64 + arm32 + i386 legs LANDED, same capture pattern:
  - aarch64: locals/params -> `[x29,off]`; globals only via
    `ldr <reg>, <name>` -> 'ldr reg,@glob,%' (address literal) + hole;
    `b.eq` lexes as 'b' '.' 'eq' -> capture rejoins dotted mnemonics;
    immediates written WITHOUT '#' (Pascal lexer reads #4 as char literal;
    engine accepts both). FIXED latent engine bug: EmitAsmA64's ldr-literal
    label detect compared the whole tail against '@glob' but the reloc form
    carries ',%' -> misrouted to the label path (dormant: no codegen caller
    used 'ldr rd,@glob' through EmitAsmA64 before).
  - arm32: locals/params -> `[fp,off]`; globals via `ldr <reg>, <name>` ->
    'ldr reg,@glob,%'; condition-suffixed b/bl (bne, bleq...) recognized as
    branch lines at capture.
  - i386: locals/params -> `[ebp±off]`; globals only via
    `mov <reg>, <name>` -> 'mov reg,@glob' (address load) + hole — the 386
    engine has no absolute-mem operand kind, unlike x86-64's AOP_GLOBAL, so
    i386 global access derefs through a register; registers restricted to
    the 32-bit-legal subset (no r8+/64-bit/xmm — clear error).
  - Engines asmtext_a64/arm32/386.inc refactored to the same
    BlockBegin/ProcessLine/BlockResolve + ProcessInlineLine API (pure
    restructure); IR_ASM cases added to ir_codegen_aarch64/arm32/386.inc.
  - Tests test_asm_a64/arm32/386.pas (locals/params + label loop + global,
    oracle output 42/55/42 identical across all 5 targets incl x86-64/rv32)
    wired into make test-aarch64 / test-arm32 / test-i386 — all green.
