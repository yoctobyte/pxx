---
track: N
prio: 30
type: feature
---

# `min("cab")` / `max("cab")` do not compile

```python
print(max("cab"))     # CPython: c
```

```
error: no matching overload
    max(Variant, Variant)
    max(Int64, Int64)
    max(Double, Double)
    max(class)
```

min/max accept a list (the `max(class)` overload is TPyList) and two scalars,
but not a string — and by extension not any other iterable that is not a
TPyList. In CPython min/max take any iterable, so a dict (iterating keys), a
set and a generator are all in scope for the same gap.

A compile error, so it is a gap rather than a silent wrong answer — filed as a
feature, not a bug. Found by the builtin × argument-type sweep against CPython.

## Gate

`make test-nilpy` + self-host byte-identical, plus min/max over str, list, dict
and set diffed against CPython.
