# bug: constant-expression evaluation ignores operator precedence

- **Type:** bug (Track A — parser / constant folding)
- **Status:** DONE 2026-06-23
- **Found:** 2026-06-23, differential sweep vs FPC
- **Severity:** medium-high (silent wrong values in any mixed-operator const:
  `const`, array bounds, enum/typed-const initializers)

## Symptom

```pascal
const C = 2*3+1;   { fpc: 7   pxx: 8 }
const D = 20-4-3;  { fpc: 13  pxx: 19 }
```

`ConstEval` was a single flat loop that, for each operator, recursively
evaluated *the entire rest* of the expression and applied the operator to it —
i.e. strictly right-to-left with no precedence and no left-associativity. So
`2*3+1` folded as `2*(3+1)=8`, `2+3*4+5` as `2+(3*(4+5))=29`,
`100 div 10 + 5` as `100 div 15 = 6`, `20-4-3` as `20-(4-3)=19`,
`2 shl 1 + 1` as `2 shl 2 = 8`. Runtime expressions were unaffected (the runtime
term/expr parser already had precedence).

The compiler's own source was bitten: a mixed-precedence array-size const folded
too small, so the self-hosted binary carried an undersized BSS buffer (BSS grew
~1.2 MB after the fix — the FPC-seeded chain had silently propagated the wrong
size byte-for-byte).

## Resolution (2026-06-23)

Fixed in commit `523e5df`.

Split `ConstEval` into proper precedence levels, mirroring Pascal:
- `ConstEvalFactor` — primary (literal / named const / paren / integer cast),
  unary `+`/`-` binding tightest. The recursive call needs explicit parens
  (`ConstEvalFactor()`) or the bare own-name reads the Result var instead of
  recursing (the standard pxx/FPC paramless-function trap).
- `ConstEvalTerm` — `* div mod and shl shr`, left-associative.
- `ConstEval` — `+ - or xor`, left-associative.

Verified vs FPC `{$mode objfpc}` across mixed-operator, left-assoc, unary-minus,
negative-literal, and `Int64()`-cast cases. Self-host byte-identical (fixedpoint
held); `make test` green. Regression: `test/test_const_precedence.pas`.
