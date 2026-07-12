---
prio: 45
---

# `sizeof(us + 0)` reports 2, not 4 — binary ops skip the integer promotions

- **Type:** bug (compat — wrong type, currently benign)
- **Track:** C — C frontend (`cparser.inc`); tag: compat
- **Status:** working
- **Found by:** while fixing [[bug-c-unary-minus-no-integer-promotion]] (same family).

## Symptom
```c
unsigned short us = 1;
sizeof(us + 0)   /* -> 2.  C says 4: both operands promote to int */
```
Same on every target, so it is CONSISTENT — which is why c-testsuite 00200 passes
anyway (its PTYPE macro takes sizeof on both sides and the error cancels). That is
luck, not correctness.

## Root cause — NOT what the title says
The guess in the ticket was wrong, and worth recording so nobody re-derives it:
**`CBinResultTk` was already correct.** `unsigned short + int` does fall through to
`tyInteger`, and every binary operator already promotes properly. Nothing about the
usual arithmetic conversions was broken.

The bug was in `ParseCSizeof`. It has a fast path that sizes an operand straight from
its SYMBOL (so `sizeof(arr)` is the array, not a pointer), and that path fired on
ANY leading identifier without ever checking that the operand ENDED there. So
`sizeof(us + 0)` matched the fast path on `us`, measured `us` alone, and never parsed
the `+ 0` at all. That is also why `sizeof(-us)` was right: it does not begin with an
identifier, so it took the general expression path.

Fix: `CSizeofIdentOperandIsWhole` — take the fast path only when the identifier (with
optional `.field` / `->field` / `[index]` selectors) is the WHOLE operand, i.e. the
next token at operand level is `)`. Bracket contents are skipped wholesale, so
`sizeof(a[i+1])` stays simple; a call like `sizeof(f(x))` is not.

The risk was never the promotion — it was regressing the fast path's many special
cases (`sizeof(*p->head)`, `sizeof(cases->c[0])`, the sizeof(arr)/sizeof(arr[0])
count idiom). The regression pins all of them down.

## Gate
C tests green + self-host byte-identical + cross (all targets — this touches every
backend's arithmetic widths).
