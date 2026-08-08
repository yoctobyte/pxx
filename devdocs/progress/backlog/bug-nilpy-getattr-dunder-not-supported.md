---
prio: 30
track: N
type: bug
blocked-by: []
---

# `__getattr__` (dynamic attribute fallback) is not supported

- **Type:** bug / missing protocol (NilPy) — **Track N**
- **Split out of** [[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]] 2026-08-09
- **Loud:** a compile error, not a wrong answer.

```python
class C:
    def __getattr__(self, name):
        return "GETATTR-" + name

print(C().missing_thing)    # CPython: GETATTR-missing_thing
```

```
pascal26:4: error: "missing_thing": no such member on this record/class
```

Re-measured at HEAD 2026-08-09: unchanged.

## Why this is the largest of the three siblings

Attribute lookup is resolved STATICALLY against the class layout, and the whole
point of `__getattr__` is to answer for names that are not in it. So the miss
has to become a runtime call rather than a compile error — which means the
compile-time "no such member" diagnostic can no longer fire for a class that
declares `__getattr__`, and every member-access site has to agree on that.

Note the existing `pydynattr_get`/`pydynattr_set` store: NilPy already has a
runtime attribute path for names it cannot resolve statically. Whether
`__getattr__` should be layered on top of that (dynattr miss → `__getattr__`)
is the design question to settle first, and CPython's own order is the answer to
match: instance dict, then class, then `__getattr__` last.

**Do not weaken the static diagnostic for classes that do NOT declare
`__getattr__`.** A typo'd attribute becoming a silent runtime miss is a much
worse trade than the feature is worth; the whole point is that the fallback is
opt-in per class.

`__setattr__`/`__delattr__` are the same family and should be scoped with it.

## Gate

`.npy` diffed against CPython: a class with `__getattr__` answering for a
missing name, a REAL attribute still winning over it, and the control that a
class WITHOUT `__getattr__` still gets the compile-time "no such member" error.
