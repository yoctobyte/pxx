---
track: N
prio: 35
type: bug
blocked-by: []
---

# `hash(x)` is not implemented

- **Type:** bug (missing builtin — a compile error, so loud) — **Track N**
- **Found:** 2026-08-11, while probing
  [[bug-nilpy-a-user-hash-dunder-is-ignored-for-dict-keys]]. A program cannot
  even ASK what pxx hashes a value to, which is what made that bug harder to
  narrow than it needed to be.

```python
print(hash("ab"), hash(1), hash((1, 2)))
```

```
pascal26: error: undefined variable (hash)
```

CPython prints three integers (the string one is salted per process, the int one
is the value itself, the tuple one is derived from its elements).

## What it should answer

pylib already computes exactly this: `PyVarHashKey(p: PPyVarRec): NativeUInt` is
the dict's own key hash, written to mirror `PyVarEq` arm for arm — int family by
value, strings by content, tuples/lists by element, a user object through its
`__hash__`. So `hash(x)` is a thin frontend intercept over the routine that
already exists, and it is the natural home for the "a `__hash__` returning a
VARIANT still has to fold to an integer" rule that the sibling ticket needs.

**Do not promise CPython's exact numbers.** CPython salts string hashing per
process (`PYTHONHASHSEED`), so `hash("ab")` is not reproducible even between two
CPython runs. What must hold is the INVARIANT: equal values hash equal, within
one run. A pydiff test must therefore compare `hash(a) == hash(b)` and
`hash(a) == hash(a)`, never the literal number.

## Gate

`make test-nilpy` + self-host byte-identical, and a `.npy` case asserting the
invariant (equal ints / equal strings / equal tuples / two `__eq__`-equal user
objects all hash equal, and `hash(x) == hash(x)`), diffed against CPython with
`tools/pydiff.py run`.
