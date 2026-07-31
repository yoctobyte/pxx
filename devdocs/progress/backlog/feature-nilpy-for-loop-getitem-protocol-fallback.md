---
track: N
prio: 25
type: feature
blocked-by: []
---

# `for x in obj:` doesn't fall back to `__getitem__`/`__len__` for a custom container

Found by proactive CPython-diff sweeping.

```python
class Box:
    def __init__(self, items):
        self.items = items
    def __getitem__(self, idx):
        return self.items[idx]
    def __setitem__(self, idx, val):
        self.items[idx] = val
    def __len__(self):
        return len(self.items)

b = Box([1,2,3])
print(b[0])       # works: 1
b[0] = 99         # works
print(len(b))     # works: 3
for x in b:       # fails
    print(x)
```
`b[idx]`/`b[idx] = v`/`len(b)` (via `__getitem__`/`__setitem__`/`__len__`)
already all work correctly. Only iterating a custom container with `for`
fails:
```
pascal26:16: error: Nil Python: pylib (count) not loaded
```
CPython supports iterating ANY object that implements `__getitem__`
(starting from index 0, stopping on `IndexError`) even without a full
`__iter__`/`__next__` — the "old-style iteration protocol" fallback. NilPy's
`for` desugars to a counted loop assuming a known container type
(list/dict/str/etc.) and has no path for a bare user class, even one that
otherwise fully implements the item-access protocol.

## Scope note

Likely related to the broader, already-tracked generator/iterator-protocol
gap (`feature-generators-yield`, `feature-nilpy-yield-outside-a-for-loop`,
and the full `__iter__`/`__next__` STOP-iteration protocol, which is a much
bigger feature) — but this specific fallback (iterate via `__getitem__`
alone, no explicit iterator object) is narrower and could plausibly land
independently of the general generator/iterator machinery: it's "counted
loop calling `obj[i]` until `__getitem__` would raise `IndexError`," which is
close in shape to how NilPy already desugars `for x in some_list:`.

Not attempted this pass — needs its own investigation into whether it's
cheap to add as a special `for` desugar case (detect a class with
`__getitem__` but no static list/dict/str type) versus properly belonging
to the larger iterator-protocol feature.

## Gate

A `.npy` case iterating a class that implements only `__getitem__`/`__len__`
(no `__iter__`), diffed against CPython, gated in `test-nilpy` + `--tier
quick` + self-host byte-identical.
