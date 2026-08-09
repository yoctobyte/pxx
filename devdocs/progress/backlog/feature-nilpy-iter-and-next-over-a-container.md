---
track: N
prio: 35
type: feature
---

# `iter(xs)` is undefined — the explicit iterator protocol

```python
it = iter(xs)          # error: undefined variable (iter)
print(next(it), next(it))
print(list(it))        # the rest, from where next() left off
```

`next()` already exists for a bare generator expression (`next(x for x in xs)`),
so the gap is `iter` itself and, with it, the idea of a RESUMABLE position over
a container. That second half is the real work: `list(it)` after two `next()`
calls must yield only the remainder, so the iterator has to hold state that
survives being passed around.

Walls visibly as an undefined name.

Related and deliberately not merged: `feature-nilpy-yield-outside-a-for-loop`
records that generators are unimplemented full stop. A user-defined `__iter__` /
`__next__` pair is a third piece again. This ticket is only the builtin over an
existing container, which is the cheapest of the three and the one real code
reaches for first.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over `iter` on a
list, tuple, set, dict (keys) and string; `next()` to exhaustion raising
StopIteration; `next(it, default)`; and consuming the remainder with `list()`
and with a `for` after partial consumption.
