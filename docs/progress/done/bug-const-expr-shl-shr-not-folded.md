# `shl` / `shr` in a constant expression not accepted

- **Type:** bug (compiler)
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-19 (discovered by `make demos`: examples/chess/chess.pas)
- **Resolved:** 2026-06-19

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

## Resolution

`ConstEval` (parser.inc) only looped over `+ - * div`. Extended its operator
loop with `shl` (tkShl), `shr` (lexed as an identifier, like the runtime term
parser), and the trivial integer siblings `mod` / `and` / `or` — all of which
previously errored in a const expression, so the change is purely additive.
`const X = 1 shl 16;` now folds to 65536. Note: `ConstEval` is a flat
right-grouping evaluator (no operator precedence); parenthesise where order
matters, same as before.

Regression test `test/test_const_bitwise_shift.pas` (shl/shr/mod/and/or + the
chess `1 shl 16` case), wired into test-core; verified output-equal on i386 /
aarch64 / arm32 too. `make bootstrap` byte-identical.

The chess demo's next blocker is unrelated — `base type not found: Exception`
(line 85), tracked separately (see feature-demo-chess).

## Log
- 2026-06-19 — opened from the demos compile-smoke dashboard.
- 2026-06-19 — fixed: shl/shr (+mod/and/or) folded in ConstEval; regression test
  added + wired; bootstrap byte-identical. Resolved.
- 2026-06-20 — commit reference (board checker): landed in 632f1c8
