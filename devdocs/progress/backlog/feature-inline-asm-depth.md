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
- Global-var operands.
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
