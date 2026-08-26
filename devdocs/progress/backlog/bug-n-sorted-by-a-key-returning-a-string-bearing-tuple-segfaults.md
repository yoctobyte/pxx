---
track: N
prio: 82
status: backlog
---

# sorted(key=f) segfaults when f returns a tuple containing a string

`sorted(l, key=f)` crashes when the key function returns a TUPLE one of whose
elements is a string. Sorting the same tuples directly is fine, and a key
returning a scalar or an all-int tuple is fine, so it is the key path
specifically.

```python
def q(a, i=7, s="hi"):
    return (a, i, s)
print(sorted([3, 1, 2], key=q))     # Segmentation fault
```

## Boundary, measured

Same file, only the return varied:

| key returns | result |
| --- | --- |
| `a + i` (scalar) | `[1, 2, 3]` |
| `(a, i)` (int tuple) | `[1, 2, 3]` |
| `(a, i, s)` (has a string) | **SIGSEGV** |

And sorting string-bearing tuples with NO key works:

```python
print(sorted([(3,"a"), (1,"b"), (2,"c")]))   # correct
```

So neither tuple comparison nor string comparison is broken on its own — it is
the combination with the `key=` path, which materialises its keys into a
separate list (`PyCallKey1` into `keys.append`, `compiler/builtin/pyeval.pas`
~5209) rather than comparing the elements in place. A managed string reaching
that list is the obvious suspect; measure before concluding.

## Provenance

Reproduced identically on HEAD (`e78cc5882` plus the uncommitted callable-value
signature work) and on `PXX_STABLE` (`stable_linux_amd64/default/pinned`), so it
is **pre-existing and unrelated to the signature work** — found while widening
that ticket's repro, where the first draft of the test used exactly this shape.
CPython prints `[1, 2, 3]`.
