---
track: N
prio: 40
type: feature
---

# `map(lambda ...)` is unimplemented and `filter` does not exist

```python
list(map(lambda v: v + 1, [1, 2]))
# error: Nil Python: map() over lambda is not implemented (int, str and float are)

list(filter(lambda v: v > 1, [1, 2, 3]))
# error: undefined variable (filter)
```

`map` exists but only with a TYPE as the first argument (`map(int, ...)`);
`filter` is absent entirely. Both fail at compile time, so nothing computes a
wrong answer — filed as a feature.

The callable-value machinery this needs is already in place: a lambda in a
name, a lambda in a list, and a lambda passed to a `Callable[...]` parameter
all work today, and `sorted` already works. So this is wiring two builtins to
the existing runtime dispatcher rather than new infrastructure. `sorted(key=)`
and `min`/`max` with a `key=` are the same shape and worth doing in the same
pass.

Found by the functions/closures sweep against CPython.

## Gate

`make test-nilpy` + self-host byte-identical, plus `map`/`filter` over a
lambda, a named def and a bound method, each consumed by `list()` and by a
`for` loop.
