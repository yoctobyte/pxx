# `shl` / `shr` in a constant expression not accepted

- **Type:** bug (compiler)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-19 (discovered by `make demos`: examples/chess/chess.pas)

## Symptom

`examples/chess/chess.pas:30` declares `TT_SIZE = 1 shl 16;`:

```
pascal26:30: error: unexpected token ()
```

A `shl` (and presumably `shr`) operator inside a **constant declaration**
expression is rejected, though `shl`/`shr` work in ordinary runtime expressions.

## Direction

Allow `shl` / `shr` in the const-expression evaluator (compile-time fold), so
`const X = 1 shl 16;` yields 65536. Track A (compiler). Confirm `shr` too; add a
const-fold test alongside the existing const-expression tests. Likely a small
gap in the const-folding operator set.

## Log
- 2026-06-19 — opened from the demos compile-smoke dashboard.
