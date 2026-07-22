---
track: N
prio: 35
type: bug
---

# NilPy: a comprehension used directly as a for-loop iterable segfaults

Found 2026-07-21 adding expression-position comprehensions.

```python
for v in [x + 1 for x in xs]:   # SEGFAULT at runtime
    print(v)
```

The same comprehension works everywhere else tested: `len([x for x in xs])`,
`"-".join(str(x) for x in xs)`, chained `zs = [y*2 for y in ys]`, and the
statement-level `ys = [x for x in xs]`. Only inlining it as the ITERABLE of a
for-loop crashes.

## Likely cause

An expression-position comprehension desugars to a hoisted hidden list plus an
appending loop (PyParseCompExprValue -> PyBuildComp -> PyParseFor). When the
comprehension is itself the iterable of an OUTER for-loop, PyParseFor is
re-entered while its own iterable is still being parsed, and the two loops'
hidden loop-variable/frame allocation appears to collide. Compiles clean, wrong
code at runtime.

## Workaround

Assign the comprehension to a name first: `tmp = [x+1 for x in xs]; for v in
tmp:` — the statement-level path (PyParseListComp) is unaffected.

## Not blocking uforth

uforth's comprehensions are all statement-level assignments or a `join(genexpr)`
argument, none of which hit this. Filed for correctness, not for the corpus.

## Fix direction

Give PyParseForIn/PyParseFor's hidden loop temps serial-unique names even under
re-entrancy (PyHiddenName may be reusing a counter that the nested call resets),
or materialise a for-loop's comprehension iterable through the statement path.

## Log
- 2026-07-22 — resolved, commit 58fff656.
