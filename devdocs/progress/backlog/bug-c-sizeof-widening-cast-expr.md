---
prio: 40  # auto
---

# C: `sizeof((long)expr)` returns 4, not 8 — widening-cast expression keeps operand width

- **Type:** bug (C sizeof-of-expression / widening ordinal cast type). Track C.
- **Found:** 2026-07-08 (fable-abc), while writing the regression test for
  bug-c-shift-result-type-battery-00200 (independent of that fix).

## Symptom
    sizeof(long)        == 8   (OK)
    sizeof((long)1)     == 4   (BUG, gcc: 8)
    sizeof((long)1 + 0) == 4   (BUG, gcc: 8)
    long v=1; sizeof(v+0) == 8  (OK)
So a WIDENING cast expression `(long)<int-expr>` is sized by the operand's width
(int, 4) instead of the cast target type (long, 8). A long VARIABLE expression is
fine — only the cast node is mis-sized.

## Likely cause
A widening ordinal cast `(long)1` (int -> tyInt64, 8 bytes) is not caught by the
narrow-int-cast path (ParseCUnary ~1480, which only handles TypeSize < 8) and
falls to AN_PTR_CAST retag. sizeof-of-expression then reads the operand node's
type/size rather than the cast's ASTTk. Check how sizeof resolves an
AN_PTR_CAST node's type (it should use ASTTk[node] = the cast target), and/or
ensure a widening int cast carries tyInt64 through to sizeof. Cf. the
float<->float cast retag family (bug-c-double-ptr-deref-narrow-to-single).

## Impact
Masked in c-testsuite 00200 (it only checks PTYPE(X) == PTYPE(X<<count) for
internal CONSISTENCY, so a uniformly-wrong long size still balances). Real code
using `sizeof((long)e)` / `sizeof((size_t)e)` for buffer math would under-size.

## Gate
sizeof of a widening cast expression matches gcc for long/long long/unsigned
long; c-conformance + corpus stay green; regression test.
