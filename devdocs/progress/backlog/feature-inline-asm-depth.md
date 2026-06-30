# Inline assembler depth

- **Type:** feature — Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §5)
- **Relation:** this ticket's scope (labels/branches, global-var operands,
  explicit memory operands) is the acceptance criteria of
  [[feature-asm-structured-ir-library]], filed 2026-06-30 as the underlying
  architecture fix (flat-byte-at-parse-time → structured IR resolved at
  codegen/link time) needed to unblock all of these. See umbrella
  [[feature-assembler-first-class-citizen]].

## Motivation

Inline asm is rudimentary (x86-64 Intel, `asm ... end` / `assembler` functions,
vars by name). Missing pieces block real asm routines and the Self-adjusting
IMT thunks for interfaces.

## Scope (priority order, see `../../developer/inline-asm.md` TODO)

- ~~Labels and branches (highest value).~~ **Done 2026-06-30** — see
  [[feature-asm-structured-ir-library]] log.
- ~~Global-var operands.~~ **Done 2026-07-01** — see Log.
- Explicit `[reg]` memory operands and SIB addressing.
- Operand-size keywords.
- AT&T syntax.

## Acceptance

Each capability covered by an asm regression test; self-host fixedpoint holds.

## Log
- 2026-06-06 — ticket opened from todo.md §5.
- 2026-06-30 — Labels + branches landed (Track A); see
  [[feature-asm-structured-ir-library]] for the implementation log and the
  keyword-mnemonic bug (`and`/`or`/`div`/`dec`/...) found and fixed alongside
  it. Next up on this ticket: global-var operands.
- 2026-07-01 — **Global-var operands landed** (Track A): `mov`/ALU/`cmp`/
  `lea` accept a global as an operand, resolved via the same absolute
  `[disp32]` addressing (`EncModRMAbs`→`EmitGlobRef`) regular codegen
  already uses for globals (non-PIE build). The actual obstacle wasn't
  encoding — it was that `EmitGlobRef`'s fixup is keyed by `CodeLen`, but
  inline asm encodes into a parse-time side buffer (`AsmBytes`) whose
  offsets aren't the operand's final code position; only the `IR_ASM`
  codegen-replay loop (`ir_codegen.inc`) knows that. Fix: a new
  `AsmGlobFix[]` (`defs.inc`) records `(AsmBytes-offset, BSS-offset)` at
  parse time (via `AsmRecordGlobalFixup`, branched into from
  `EncModRMAbs`'s existing `EncToAsmBuffer` flag — the same flag already
  used to redirect typed-encoder output between `Code[]` and `AsmBytes`),
  and the replay loop calls the real `EmitGlobRef` at the matching position
  instead of copying the 4-byte placeholder literally. New `AOP_GLOBAL`
  operand kind, widened through `AsmModRM`/`AsmOpSizeOf`/`AsmEncodeALU`/
  `lea` (test/xchg/unary/shifts/setcc/cmovcc needed no changes — already
  generic via `AsmModRM`). Three forms still cleanly rejected (fast-path
  typed encoders hardcode `[rbp+disp]`): `mov global,imm`, `push global`,
  `pop global`. `test/test_asm_global.pas` (multiple blocks, multiple
  procedures, multiple globals, plus a `lea`-computed address checked
  against Pascal's own `@g`) in `make test`. Self-host + FPC bootstrap both
  byte-identical. Next up: explicit `[reg+disp]` memory operands + SIB.
