# Char literal in a constant expression: `ConstEval` rejected `'a'`

- **Type:** bug (compiler — const-expression evaluator)
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-21
- **Resolved-in:** c45b785
- **Relation:** self-discovered while implementing
  `feature-local-typed-constant`. The chess piece-glyph tables
  (`array[..] of Char = ('.', 'P', ...)`) need it; the gap also affected GLOBAL
  char-array typed consts, so it predates the local feature.

## Problem

`ConstEval` (parser.inc) handled integer / boolean / `Ord`-style ordinals but not
a character literal. A single-quoted `'a'` lexes as `tkString` (token Kind 3) of
length 1, which fell through to no primary alternative:

```text
const W: array[1..3] of Char = ('a','b','c');
pascal26: Expected: ), but got: a (Kind: 3)
pascal26: error: unexpected token ()
```

Reproduced on a plain global typed const, so not specific to the local-const
work — any const-expression position wanting a char value hit it.

## Fix

In `ConstEval`, add a primary alternative: a length-1 `tkString` evaluates to its
character code (`Ord(SVal[1])`). Compile-time only; no codegen change.

## Acceptance

- `const W: array[lo..hi] of Char = ('.', 'P', ...)` parses (global and local).
- `examples/chess` `PieceGlyph` / `MoveText` glyph tables compile.

## Log
- 2026-06-21 — found + fixed inline during feature-local-typed-constant
  (c45b785); filed retroactively to document the self-discovered bug. Covered by
  `test/test_local_typed_const.pas` (the Char-array case). Track A.
