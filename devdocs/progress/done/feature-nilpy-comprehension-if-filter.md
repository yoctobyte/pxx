---
track: N
prio: 30
type: feature
---

# NilPy: comprehension `if` filters — `[x for x in xs if x > 1]`

Unsupported everywhere (statement-level and expression-position alike):
`error: Nil Python: a conditional expression needs an else` — the filter's
`if` is parsed as a ternary head. Loud, not silent; found while testing
bug-nilpy-comprehension-as-for-iterable-segfaults (which fixed the iterable-
position hoist ordering; filters are orthogonal). Desugar: wrap the append in
`if <cond>:` inside PyBuildComp's loop.
Gate: len([x for x in [1,2,3] if x > 1]) = 2, CPython-diffed; test-nilpy green.

## Log
- 2026-07-22 — resolved, commit e4792549.
