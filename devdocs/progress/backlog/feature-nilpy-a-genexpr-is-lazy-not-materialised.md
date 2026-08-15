---
track: N
prio: 25
type: feature
blocked-by: []
summary: "A genexpr's elements are built EAGERLY and then walked by a cursor, so single consumption is right but an INFINITE genexpr still cannot be expressed and side effects all happen at construction. True laziness means a TPyIter whose mapping is the element expression."
---

# A genexpr should be lazy, not materialised-then-walked

Split out of [[bug-nilpy-a-generator-expression-is-not-consumed-once]] when the
observable half landed (2026-08-15). Consumption is now correct:

```python
g = (x for x in [1, 2])
print(next(g), list(g))     # 1 [2] — right
```

What is still eager is the BUILD:

```python
def naturals():
    n = 0
    while True:
        yield n
        n += 1

g = (x * 2 for x in naturals())   # hangs: every element is built first
```

...and side-effect ordering: `(print(x) for x in xs)` prints everything at
construction, where CPython prints nothing until the first `next`.

## The shape a fix probably takes

`map`/`filter`/`zip`/`enumerate` are already lazy `TPyIter` cursors, so a
genexpr wants to BE one rather than to gain a second lazy mechanism: build a
`pyiter_map` over the source with the element expression as the mapping, and a
`pyiter_filter` for an `if` clause.

The element expression is a token SPAN, and turning a token span plus its free
names into a callable with its captures bound is exactly what the lambda lifter
does (`PyLambdaBodyIsLiftable`, `PyCompileLambdaBody`, `pyboundfn_*`). So the
plausible route is to reuse it rather than write a third mechanism — and its
existing fallback (the shape it declines to lift keeps the eager path) is a
ready-made safety net for whatever the lifter cannot take.

A multi-`for` genexpr (`(x for a in aa for x in a)`) needs a nested cursor;
check whether that is worth the first slice or should keep the eager path.

## Gate

`.npy` diffed against CPython: an infinite source with `next` and
`itertools.islice`-shaped consumption; side-effect ORDER (`print` inside the
element expression); a filter clause; a genexpr over a genexpr; one capturing
an enclosing local that CHANGES between construction and consumption (CPython
binds the outermost iterable eagerly and everything else late — that asymmetry
is the subtle part); plus every shape
`test_nilpy_genexpr_is_consumed_once.npy` already covers, unchanged.
