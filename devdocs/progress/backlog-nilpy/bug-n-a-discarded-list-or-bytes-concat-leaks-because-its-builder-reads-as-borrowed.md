---
type: bug
track: N
prio: 35
status: open
slug: bug-n-a-discarded-list-or-bytes-concat-leaks-because-its-builder-reads-as-borrowed
summary: "A bare expression statement `a + b` over lists, or `bv + b\"x\"` over bytes, leaks two objects per execution (live 13 -> 2013 over 1000 passes). `y = a + b` is flat. pylist_concat and pybytes_concat build `r := Create; r.put(...); Result := r`, and ClassifyProcResultFresh calls that borrowed, because LocalUseEscapes counts any method call on the local as an escape. So the discard binder does not release the result."
---

# A discarded list or bytes concat leaks because its builder reads as borrowed

Measured 2026-10-02 (frankuser), x86-64, census at N=1 and N=1001:

| statement in a loop | live |
| --- | --- |
| `y = bv + b"z"` | 11 -> 11 |
| `bv + b"x"` | 13 -> 2013 |
| `y = a + b` | 11 -> 11 |
| `a + b` | 13 -> 2013 |

`PXXDBG=p.fresh:*` reports `pylist_concat FALSE arg=-1` and
`pybytes_concat FALSE arg=-1`. Both bodies return a local built by
`Create` and filled with `r.put(i, ...)`. The rule in LocalUseEscapes is
deliberately conservative: a method call on the local may keep Self.

## Shape of a fix

Per-method "Self does not escape": run LocalUseEscapes over a method's own
body with Self as the local, and record the verdict per proc. Methods
compile before their callers within pylib, so a later
ClassifyProcResultFresh can treat `r.m(...)` as harmless when m's verdict is
"does not escape". `put`, `append`, `at` and the like qualify. Anything with a
cast or a store of Self stays an escape. This widens what the discard binder
releases, so it needs a tier and a HEAP_DEBUG sweep, not just this repro.

Low priority: a bare `a + b` statement is rare in real code. The lambda
`return` of the same value, which used to give None, was fixed separately
(bug-n-a-lambda-returning-a-captured-heap-value-yields-none).
