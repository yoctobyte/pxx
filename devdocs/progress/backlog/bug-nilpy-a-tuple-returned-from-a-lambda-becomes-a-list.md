---
track: N
prio: 50
type: bug
summary: "NilPy: a tuple literal returned from a lambda degrades to a list — `(lambda x: (x, x+1))(3)` prints [3, 4] and type().__name__ says 'list', while the identical expression returned from a def stays a tuple"
---

# A tuple returned from a lambda becomes a list

- **Type:** bug (silent wrong type) — **Track N**
- **Found:** 2026-08-07, bughunting with `tools/pydiff.py`.

## Measured (self-hosted fixedpoint at `8f1852f27`)

```python
t = (1, 2)
print(t)                        # CPython (1, 2)   pxx (1, 2)   agrees

def g(x):
    return (x, x + 1)
print(g(3))                     # CPython (3, 4)   pxx (3, 4)   agrees

f = lambda x: (x, x + 1)
print(f(3))                     # CPython (3, 4)   pxx [3, 4]   WRONG

print(type(f(3)).__name__, type(g(3)).__name__, type(t).__name__)
# CPython: tuple tuple tuple
# pxx    : list  tuple tuple
```

So the tuple tag survives a bare literal and a `def` return, and is lost only
through the **lambda** return path.

## Why this is a bug and not a documented divergence

`devdocs/dev/nilpy-semantics-divergences.md` accepts that a NilPy tuple is
mutable, on the ground that no working CPython program can observe it, and
states that *"everything else about a tuple is already CPython-exact:
`type(t).__name__`, `isinstance(t, tuple)`, …"*. This case is on the wrong side
of that line, by that page's own worked example: printing a returned pair and
branching on `type(...).__name__` / `isinstance(..., tuple)` are things ordinary
working CPython code does, and here they answer differently depending on whether
the producer was a `def` or a lambda. That doc's claim needs narrowing once this
is fixed, or amending if it is not.

Related but distinct — that one is about the three container types being
indistinguishable in general, this one is a tag lost on one specific path:
[[bug-nilpy-list-tuple-and-set-are-indistinguishable-to-isinstance]].

## Not yet investigated

Whether the lambda **body-compile** path (`PyCompileLambdaBody` / the lifted
`$pylamN` proc in `compiler/pyparser.inc`) builds the literal through a
different constructor than the statement path, or whether the tag is lost when
the variant result crosses the bound-fn return convention. Measure both before
concluding — do not reason it out.

## Gate

Per-fix loop. A `.npy` test asserting `type(...).__name__` and `print()` for a
tuple literal returned from a lambda, from a def, and bound directly — plus
`isinstance(..., tuple)` — diffed against CPython with `tools/pydiff.py`.
