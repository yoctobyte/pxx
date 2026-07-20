---
track: N
prio: 30
type: bug
---

# NilPy: print() of a variant holding a list/dict shows `<object>` not its repr

Found 2026-07-21 adding variant slices. A variant that holds a TPyList/TPyDict
(e.g. the result of slicing a variant, or `x or []` stored in an Any) prints as
`<object>` instead of `[1, 2]`.

```python
def f(t: Any) -> Any:
    return t[:2]
print(f([1, 2, 3, 4]))   # <object>, CPython: [1, 2]
```

The container is correct — `len()` and indexing it work; only print's repr of a
VARIANT whose payload is a container falls back to the generic object path
instead of pyvar_repr / pylist_repr. Likely the write path for a VT_OBJECT
variant does not dispatch to the container repr the way a statically-typed list
does.

Not blocking uforth (it slices bytes, whose print path is separate). Filed for
correctness.
