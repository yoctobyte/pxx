---
track: N
prio: 30
type: bug
summary: "A NilPy `def min(x, y, z)` compiles but is silently NOT called — pylib's all-Variant 3-arg min outranks it, so the program gets the builtin's answer"
---

# A user `def` loses to a pylib overload of the same arity — silently

- **Type:** bug (NilPy name resolution / overload ranking) — **Track N**
- **Found:** 2026-08-03, while gating
  [[feature-nilpy-min-max-variadic-more-than-two-args]]. Not caused by it:
  that fold cannot fire at arity 3 (pylib declares a 3-argument min, and the
  fold is guarded on no routine of that arity existing), so this call takes
  the ordinary overload path start to finish.

## Measured

```python
def min(x: int, y: int, z: int) -> int:
    return 100


print(min(1, 2, 3))     # CPython: 100     pxx: 1
```

It compiles clean and prints `1` — pylib's `min(const a, b, c: Variant)` was
chosen over the routine the programmer wrote three lines up. In Python a
module-level `def` shadows a builtin outright; here it is merely one more
overload candidate, and it loses.

Shadowing DOES work where pylib has no same-arity candidate:

| shape | pylib candidate at that arity | result |
| --- | --- | --- |
| `def min(x, y)` + `min(1, 2)` | yes (`Int64,Int64` / `Variant,Variant`) | **100 — correct** |
| `def min(x, y, z)` + `min(1, 2, 3)` | yes (all-Variant) | **1 — WRONG** |
| `def min(a..e)` + `min(1, 2, 3, 4, 5)` | none | **100 — correct** |

So the 2-argument case ranks the user's `Integer, Integer` above the Variant
pair and wins, while the 3-argument case has only a Variant candidate on the
pylib side and the user's exact-typed one still loses. That asymmetry is the
thing to explain before fixing — the ranking that gets it right at 2 args
should get it right at 3.

## Why it matters more than the arity it was found at

The wrong answer is SILENT and the shadowed name is a builtin, so the program
reads as if it calls the function on screen. `min`/`max` are the instance
found; nothing here is specific to them — any NilPy `def` whose name collides
with a pylib routine at the same arity is a candidate for the same shape.
Worth checking `sum`, `len`, `abs`, `sorted`, `round` in the same pass.

## Shape of a fix

A NilPy user `def` at module scope should not merely rank against the pylib
builtins, it should SHADOW them — the same "no user shadow" test the
`enumerate`/`zip`/`min`/`max` parser branches already apply via
`FindSym`/`PyAnyProcWithArity` before claiming a call, but applied in the
overload resolver rather than per-branch. Care needed: pylib routines are
ordinary Pascal procs in the same table, so "declared by the NilPy program"
has to be a real predicate (declaring unit / `NilPyUserCode` at declaration
time), not a name list.

## Gate

A `.npy` shadowing `min`, `max` and at least two other pylib builtins at 1, 2,
3 and 5 arguments, each diffed against CPython, plus the existing pylib call
sites still resolving to pylib when NOT shadowed.
