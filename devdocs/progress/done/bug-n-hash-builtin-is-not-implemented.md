---
track: N
prio: 35
type: bug
blocked-by: []
status: done
owner: claude-A
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

## Resolution (2026-08-11)

`pyhash_v` exposes `PyVarHashKey` — the dict's own key hash — and a frontend
intercept lowers `hash(x)` to it, gated on `procIdx < 0` so a user `def hash`
shadows it like every other builtin here. Nothing new was computed: the value
already existed and simply had no name in the language.

Matches CPython on every row, and every row is an INVARIANT rather than a
number (CPython salts string hashing per process, so a literal expectation is
untestable by construction):

- equal ints / strings / tuples hash equal; unequal ones do not
- two `__eq__`-equal objects with a user `__hash__` hash equal — the consistency
  this pairs with, and the reason
  `bug-nilpy-a-user-hash-dunder-is-ignored-for-dict-keys` was hard to narrow
  without it
- `hash(True) == hash(1)` and `hash(2.0) == hash(2)`, the cross-tag equalities
  `PyVarEq` already promises
- a user `def hash` still wins

Gate: `make test-nilpy` EXIT=0, `gate.sh quick` GREEN. New
`test/test_nilpy_hash_builtin.npy`. Needs a pin before other lanes see it
(`compiler/builtin`).

## Log
- 2026-08-11 — resolved, commit da16b2be9.
