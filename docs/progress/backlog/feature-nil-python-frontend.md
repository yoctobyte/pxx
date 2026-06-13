# Nil Python frontend (`.npy`)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-13 (tracking the long-standing plan as a board ticket)

## Motivation

A Python-shaped frontend to replace BASIC as the showcase dialect: short,
readable grammar without CPython's dynamic-everything machine. Statically typed
with local type inference and a **closed scalar-Variant escape valve** — 95% of
code stays unboxed and compiles to fast native via the existing IR. Full Python
is a non-goal (no `eval`, no self-modification, no open type universe).

Source extension `.npy` ("Nil pY"); `.py` stays unsupported on purpose.

## Intended surface

A new lexer + parser that build the **shared AST**, then call `CompileAST()` —
the whole backend (linear IR → x86-64/cross emission → ELF) is reused, as the
BASIC frontend already demonstrates (~620 lines). The cost is mostly semantics:
first-binding type inference, numeric-widening unification, `tyVariant`
promotion on scalar-set unify failure, hard error otherwise.

## Plan + specs

Full design is in:
- `docs/developer/nil-python-plan.md` — phased plan, settled design decisions,
  verified reuse points (frontend dispatch `compiler/compiler.pas:134`, shared
  AST `compiler/defs.inc:62-112`, `CompileAST` handoff `ir_codegen.inc:1989`).
- `docs/developer/nil-python.md` — dialect notes.

Open decision flagged in the plan: Variant helpers as compiler-emitted runtime
routines vs linked RTL symbols (no general linker exists). Resolve in Phase 1.

## Acceptance

`.npy` programs (typed locals, inference, `tyVariant` escape valve, classes via
VMT) lex/parse/compile/run with oracle tests; self-host fixedpoint holds for the
existing Pascal compiler (the new frontend is additive, must not perturb it).

## Log
- 2026-06-13 — ticket opened to track the existing plan on the board.
