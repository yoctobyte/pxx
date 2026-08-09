---
prio: 55
track: N
type: bug
blocked-by: []
status: done
---

# `zip()` inside a comprehension fails to parse

- **Type:** bug (NilPy; valid CPython refused at compile time) — **Track N**
- **Found:** 2026-08-09, realistic-program sweep (a Vec/Mat class whose
  `__add__` is `Vec([a + b for a, b in zip(self.xs, other.xs)])`).

```python
[a + b for a, b in zip(A, B)]
```

```
Expected: :, but got:   (Kind: 77, Line: 18)
pascal26:18: error: unexpected token
```

The diagnostic points at the closing bracket and says a colon is missing, which
is unhelpable-with: there is no statement here to put a colon on.

## Cause

`PyParseFor`'s zip intercept routes to `PyParseForZip`, a **statement** desugar:
it demands the header's `:` and then parses a SUITE. A comprehension reaches the
same intercept and dies on the `Expect(tkColon)`.

## Fix

Take the intercept only outside a comprehension (`PyCompTarget < 0`). A
comprehension then needs no zip handling at all: `zip()` is already a working
EXPRESSION yielding a list of pairs (`list(zip(A, B))` has always been right),
so it falls through to `PyParseForIn` and lands on the two-name pair-unpack path
that a plain list of pairs already takes. One condition, no new machinery — the
capability was there, the intercept was just standing in front of it.

## Verified

`test/test_nilpy_zip_in_a_comprehension.npy` — list, dict and generator
comprehensions over zip, with a filter, with uneven and empty operands, plus the
statement form and a method using it, all diffed against CPython's own output.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
