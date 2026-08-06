---
track: N
prio: 50
type: bug
summary: "NilPy: isinstance(t, list) is True for a tuple, so a working CPython program that branches on it takes the wrong arm — `flatten` over [[1,2], (3,4), 5] flattens the tuple too. The tuple being MUTABLE is not a bug (see the divergences doc); this is."
---

# `isinstance(<tuple>, list)` is True

- **Type:** bug (silent wrong branch) — **Track N**
- **Found:** 2026-08-06, measuring what a NilPy tuple actually is.
  Pre-existing (identical on `pinned`).

## The rule this is filed against

> **If code works on CPython, it must work on NilPy.** NilPy is *upward
> compatible* with the reference implementation: accepting things CPython
> rejects is a language feature, not a defect.

(User, 2026-08-06 — the same contract already stated at the top of
`devdocs/dev/nilpy-semantics-divergences.md`.)

A NilPy tuple is a `TPyList` and is therefore **mutable** — `t[0] = 9`,
`t.append(4)` and `del t[0]` all succeed where CPython raises. Under the rule
above that is **not a bug**: no working CPython program does it. It is recorded
as a deliberate divergence in the divergences doc, not here.

This ticket is the half that *is* a bug, because a program CPython accepts and
runs correctly behaves differently.

## Measured

```python
def describe(x):
    if isinstance(x, list):  return "list of %d" % len(x)
    if isinstance(x, tuple): return "tuple of %d" % len(x)
    return "scalar"

print(describe([1, 2]))          # CPython list of 2    pxx list of 2
print(describe((1, 2)))          # CPython tuple of 2   pxx list of 2   WRONG
```

And the idiom that makes it matter — narrowing an untyped value before
flattening it:

```python
def flatten(v):
    out = []
    for e in v:
        if isinstance(e, list):
            out.extend(e)
        else:
            out.append(e)
    return out

print(flatten([[1, 2], (3, 4), 5]))
# CPython [1, 2, (3, 4), 5]
# pxx     [1, 2, 3, 4, 5]        <- the tuple was flattened too
```

Nothing raises. `isinstance(x, list)` is the ordinary way NilPy code narrows a
dynamically-typed value, so this reaches any program that keeps tuples and lists
apart on purpose — exactly what a `(row, col)` pair inside a list of rows is.

`isinstance(t, tuple)` is correctly True, and `type(t).__name__` correctly says
`tuple`; only the `list` answer is wrong.

## Shape of a fix

The representation can stay shared — this does not need a separate `TPyTuple`.
A flag on the instance recording "built as a tuple", set where the parser builds
a parenthesised tuple (*"A parenthesised TUPLE is built as a TPyList"*), and read
by the `isinstance` lowering so `list` answers False for it and `tuple` answers
True.

If that flag lands, note that it is also what a future
`bug-nilpy-tuple-is-mutable`-style change would key off, should the divergence
ever be revisited — but do not add the mutation checks under this ticket:
rejecting `t[0] = 9` rejects nothing a working CPython program does, and costs a
check on every store.

## Gate

Per-fix loop. A `.npy` test over `isinstance` against `list` / `tuple` / `dict`
for a tuple, a list and a scalar, plus the `flatten` idiom above, diffed against
CPython with `tools/pydiff.py`. The read paths (index, slice, iterate, `len`,
`==`, `+`, dict key, unpacking) must stay working — they are all correct today.
