# Inline assembler depth

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §5)

## Motivation

Inline asm is rudimentary (x86-64 Intel, `asm ... end` / `assembler` functions,
vars by name). Missing pieces block real asm routines and the Self-adjusting
IMT thunks for interfaces.

## Scope (priority order, see `../../developer/inline-asm.md` TODO)

- Labels and branches (highest value).
- Global-var operands.
- Explicit `[reg]` memory operands and SIB addressing.
- Operand-size keywords.
- AT&T syntax.

## Acceptance

Each capability covered by an asm regression test; self-host fixedpoint holds.

## Log
- 2026-06-06 — ticket opened from todo.md §5.
