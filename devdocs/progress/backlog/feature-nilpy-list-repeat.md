---
track: N
prio: 40
type: feature
---

# NilPy: `[0] * 4` (list repeat) is not lowered

Found 2026-07-20 finishing [[bug-a-nilpy-str-repeat-local-infers-as-int]] —
the string half is fixed, this half was never implemented.

```python
xs = [0] * 4
print(xs, len(xs))     # CPython: [0, 0, 0, 0] 4
                       # pxx: error: no overload of len matches these arguments
```

`s * n` on a STRING lowers to pylib `pystr_repeat`; the list case needs the
same shape — a `pylist_repeat(l: TPyList; n: Int64): TPyList` returning a new
list with the elements repeated, plus the parse-time tag (tyClass/TPyList) so
an inferred local knows what it holds. Both operand orders, and `n <= 0`
yields an empty list.

Note Python's list repeat copies REFERENCES, not elements — `[[0]] * 3` gives
three aliases of the same inner list — so the helper must copy the variant
slots as-is, not deep-copy them.

## Gate

`test-nilpy` green + `--tier quick` + self-host byte-identical, with `[0] * 4`,
`4 * [0]`, `[] * 3`, `[0] * 0` and a nested `[[0]] * 2` (mutate the inner list
and observe the aliasing) matching CPython.
