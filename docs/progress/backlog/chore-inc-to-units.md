# `.inc` → real `.pas` units refactor

- **Type:** chore
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §6)

## Motivation

The `{$include}` soup is an accepted single-translation-unit hack, not the
target architecture. The inline-unit model (`unit/interface/implementation`,
`uses`) already supports the move — no separate-compilation feature needed.

## Scope

- **RTL/library units move early** (low risk, real payoff).
- **Compiler self-split is last** (stress-tests unit support against the compiler
  itself; must hold self-host fixedpoint; payoff is human-readability only).
- Write new code as proto-units meanwhile.
- Seam principle: algorithm/table → library; token-stream + symtab plumbing →
  core. `asmenc.inc` is the live example to split.

## Acceptance

Targeted `.inc` files become real units with the suite green and self-host
fixedpoint intact at each step.

## Log
- 2026-06-06 — ticket opened from todo.md §6.
