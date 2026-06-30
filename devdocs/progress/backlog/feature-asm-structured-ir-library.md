# Unify inline asm onto the existing per-target text-assembler engine

- **Type:** feature (compiler architecture) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30 (corrected same-day after discovering prior art —
  see Log)
- **Relation:** foundation of [[feature-assembler-first-class-citizen]]; closes
  TODO #1-2 of `devdocs/developer/inline-asm.md` (labels/branches, global-var
  operands) as a side effect; prerequisite for
  [[feature-asm-textual-emit-mode]] and [[feature-asm-source-frontend]];
  **supersedes the "build new per-target encoders" framing of**
  [[feature-inline-asm-multi-arch]] — see correction note there.
- **Owner split (2026-06-30):** this is **layer 2** (Track A — symbolic
  resolution: labels, frame slots, global relocations) on top of **layer 1**,
  [[feature-asmcore-encoder-library]] (Track B — the clean mechanical
  encoder library, `lib/asmcore/`). Once layer 1 has enough ISA coverage,
  this ticket also covers migrating `ir_codegen*.inc` and `asmenc.inc` onto
  it, retiring the legacy `asmtext*.inc`/`x64enc.inc`/`rv32enc.inc`/
  `xtensaenc.inc` emitters. Below, "the existing engine" refers to those
  legacy emitters as an interim target until layer 1 is ready to take over —
  don't build new logic against them once `lib/asmcore` covers the same
  ground.

## Corrected understanding (read this first)

This ticket was originally going to propose a brand-new structured
instruction-list IR. That was wrong — **it already exists**, just not wired
to user-facing inline asm:

`compiler/asmtext.inc` + `asmtext_386.inc` / `asmtext_a64.inc` /
`asmtext_arm32.inc` / `asmtext_rv32.inc` / `asmtext_xtensa.inc` implement
`EmitAsmX64` / `EmitAsm386` / `EmitAsmA64` / `EmitAsmArm32` / `EmitAsmRv32` /
`EmitAsmXtensa` — **one per target, all six already exist**. Each takes an
interleaved `array of const` (instruction-text lines + `%`-hole int values),
and already has:

- **Label definitions and forward/backward jump resolution** (`AsmLblName`/
  `AsmLblPos`/`AsmFwName`/`AsmFwPatch` bookkeeping in `asmtext.inc`, same
  pattern in every per-target file) — TODO #1 in `inline-asm.md` is already
  solved here.
- **Global/data relocation operands** (`@glob`/`@data` syntax → `EmitGlobRef`/
  `EmitDataRef`, confirmed present in all six `asmtext_*.inc` files) — TODO
  #2 in `inline-asm.md` is already solved here too.

It's used today as an internal codegen-authoring convenience — `ir_codegen*.inc`
backends call these with literal Pascal string constants instead of hand
writing raw bytes. Call-site counts show very uneven adoption per backend
(2026-06-30 audit): `ir_codegen.inc`(x64) 3, `ir_codegen386.inc` 4,
`ir_codegen_aarch64.inc` 10, `ir_codegen_arm32.inc` 16,
`ir_codegen_riscv32.inc` 11, `ir_codegen_xtensa.inc` 40 — xtensa/arm32/aarch64/
riscv32 lean on it heavily, x64/i386 (older backends) mostly still call typed
`x64enc.inc`/raw `EmitB` directly. The closed ticket that built the xtensa
emitter (`devdocs/progress/done/feature-xtensa-asm-emitter.md`) says outright:
"it doubles as the backend for eventual Xtensa inline `asm … end`" — this work
was always the intended direction, just never finished.

`compiler/asmenc.inc` (the actual `asm...end` / `assembler` Pascal-block
parser) is a **separate, older, x86-64-only implementation** that does not
use any of the above — it encodes straight into a flat byte buffer at parse
time with no symbolic/relocation layer, which is the real reason labels,
branches, and globals don't work in inline asm today.

## Goal

Wire `compiler/asmenc.inc`'s parser onto the existing `EmitAsmX64` /
`EmitAsm386` / `EmitAsmA64` / `EmitAsmArm32` / `EmitAsmRv32` / `EmitAsmXtensa`
engines instead of its own flat-byte path. Concretely:

- The `asmtext_*.inc` engines currently expect their full instruction list as
  a compile-time-constant `array of const` (literal strings the compiler's
  own author wrote). User-typed inline asm is parsed at **runtime** (while
  `pxx` is compiling someone's `.pas` file), so the inline-asm parser needs to
  build an equivalent runtime line list (mnemonic text + bound hole values)
  instead of a literal array-of-const, then drive the same label/jump/operand
  classification logic. This is the one real piece of new plumbing — not a
  new IR, a new *caller* of the existing one.
- Bare local/param identifiers (today resolved via `FindSym` → frame slot in
  `asmenc.inc`) get translated to `%`-hole values (frame disp) the same way
  codegen already does.
- Bare **global** identifiers get translated to `@glob`/`@data` operands with
  the symbol's resolved offset — new glue, but small: `asmenc.inc` already
  does the local-symbol lookup, this extends it to globals and routes through
  the relocation operand the engine already supports.
- Once routed through `EmitAsmX64` et al., `jmp`/`jcc` to a bare label name
  inside the block just works — the engine already resolves those.

## Per-target rollout

Because all six `EmitAsmXxx` engines already exist (with varying maturity —
see call-site counts above), multi-arch inline asm becomes **wiring the
parser-side identifier resolution per target**, not building six new
encoders from scratch. Land x86-64 first (closes
[[feature-inline-asm-depth]] TODO #1-2), then i386/aarch64/arm32/riscv32/
xtensa — see corrected scope note on [[feature-inline-asm-multi-arch]].

## Scope (this ticket)

- Runtime instruction-line builder that feeds `EmitAsmX64` (start with x64).
- Local-identifier → `%`-hole translation (port existing `asmenc.inc` logic).
- Global-identifier → `@glob`/`@data` translation (new).
- Label/jump pass-through (no new code needed beyond routing into the engine).
- Explicit `[reg+disp]` / SIB memory operands: check whether
  `AsmTextOperand`'s existing memory-operand classification (`asmtext.inc`
  line ~169, kind 2 = `[base+disp]`) already covers this before building
  anything new — looked like it does for codegen-authored text; confirm it's
  reachable from user-typed operands too.
- Leave operand-size keywords and AT&T syntax to [[feature-inline-asm-depth]]
  (lower priority there; this change doesn't block them).

## Acceptance

- All existing asm tests (`test_asm.pas`, `test_asm_func.pas`,
  `test_asm_swap.pas`) green, unchanged behavior.
- New regression tests: a label/branch loop inside `asm...end`, a global-var
  read/write inside `asm...end`, on x86-64 first.
- Self-host byte-identical; `make test` green.

## Self-hosting constraint

Same as `asmenc.inc` today (see `devdocs/developer/inline-asm.md` bottom
section): no string `+` on the hot path, build strings with `AppendChar` —
the bootstrap compiler must compile this file. (`asmtext.inc` already
observes this discipline — match it.)

## Log
- 2026-06-30 — Opened, then corrected same-day: original draft proposed a new
  structured IR; audit of `compiler/asmtext*.inc` found the label/relocation-
  aware engine already exists per target. Rewrote scope to "wire inline-asm
  onto it" instead of "build it." (Track B, filing Track A-scope ticket per
  convention.)
- 2026-06-30 — **TODO #1 (labels + branches) landed** (Track A), closing the
  "highest value" item — but via a narrower path than this ticket's full
  scope: `compiler/asmenc.inc` did **not** migrate onto `asmtext.inc`'s
  `array of const`-based engine (that's a poor fit for text parsed at compile
  time from a user's `.pas` source, vs. literal arrays a codegen author
  writes). Instead, only the new branch-target operand (jmp/call/jcc) routes
  through `lib/asmcore`'s `AsmEncodeX64` (`PatchOp(4)`), with a local label
  table + fixup list living in `AsmParseBody` itself (same pattern as
  [[feature-asm-source-frontend]]'s `compiler/asmfront.inc`). Everything else
  in `asmenc.inc` (mov/ALU/shifts/unary/stack/setcc/cmovcc) is untouched,
  still the original `x64enc.inc`-based encoder. So this ticket's bigger
  goal — retiring the legacy emitters by migrating `ir_codegen*.inc` and the
  *rest* of `asmenc.inc` onto a shared engine — remains open and is, per
  user sequencing call, explicitly **deprioritized ("latest")** relative to
  the inline-asm (head 1) and `.asm`-frontend (head 3) user-facing work.
  Also surfaced and fixed in the same pass: `and`/`or`/`xor`/`not`/`div`/
  `mod`/`shl`/`inc`/`dec` lex as Pascal keyword tokens, not `tkIdent`, so
  `AsmParseBody`'s "skip stray punctuation" gate silently swallowed them —
  most of the documented "supported" ALU/shift table was actually broken for
  these mnemonics; fixed by widening the gate (`AsmTokIsWordLike`) rather
  than touching the lexer. `test/test_asm_branch.pas` (label + `jg` loop),
  `test/test_asm_keywords.pas` (and/or/xor/not/dec/div regression), both in
  `make test`. Self-host + threadsafe-self-host byte-identical.
