---
track: N
prio: 30
type: bug
summary: "NilPy: `d[key()] += 1` calls key() TWICE — the augmented-subscript desugar re-evaluates the base and index. CPython evaluates each once. The stored value is correct; only a side-effecting index is observable."
---

# An augmented subscript evaluates its index twice

- **Type:** bug (semantic divergence) — **Track N**
- **Found:** 2026-08-06, while fixing
  [[bug-nilpy-augmented-assign-through-a-variant-subscript-is-dropped]].
  **Pre-existing on both subscript paths**, not introduced by that fix.

## Measured

```python
calls = []
def key():
    calls.append(1)
    return "n"

e = {"n": 0}
e[key()] += 1
print(e, len(calls))       # CPython {'n': 1} 1     pxx {'n': 1} 2
```

Same on a variant base (`d["a"][key()] += 1`). The **stored value is correct**
in every case — only the extra evaluation is observable.

## Why it is prio 30 and not higher

It is a deliberate, documented trade, not an oversight.
[[feature-nilpy-augmented-subscript-assign]] chose it when it made `d[k] += 1`
work at all: *"the index expression is evaluated twice, which is the same trade
the `del d[k]` rewrite makes and is invisible for the pure index expressions the
corpus uses."* That is still true — an index with side effects is rare, and a
NilPy program that hits this is unusual.

It is filed because "rare" is not "never", and because the reasoning above lives
in a resolved ticket where nobody will find it. A future reader measuring
`len(calls)` deserves to find this rather than re-derive it.

## Shape of a fix

Bind the base and the index to hidden temps once, then read and write through
them — the same thing `PyMakeVariantSetItem` already does for the *value*
(`__py_setval`, added for chained assignment). Both paths want it: the
default-indexed-property desugar in `parser.inc` and the variant arm beside it.

Do both together or neither, so the two spellings cannot drift apart — the last
two bugs in this family were exactly "one path was fixed and its sibling was
not".

## Gate

Per-fix loop. A `.npy` test counting calls to a side-effecting index function
under `+=` on a static base, a variant base, and `del`, diffed against CPython
with `tools/pydiff.py`.
