---
track: N
prio: 20
type: bug
blocked-by: []
summary: "`str.__name__` / `int.__name__` raise AttributeError: 'type' object has no attribute '__name__'. A USER class answers correctly, so only the builtin-type value (VT_BTYPE) is missing the attribute. Clean Python-shaped error, not a crash."
status: backlog
---

# `__name__` on a BUILTIN type is unimplemented

- **Type:** bug (NilPy attribute surface) — **Track N**.
- **Found:** 2026-08-17 by frank2, splitting it out of
  [[bug-n-a-type-as-a-default-parameter-value-segfaults-when-the-default-is-taken]],
  where it was the one row that did not become CPython-equal. It is NOT that
  bug and was not caused by its fix — the identical failure predates it.

## Repro

```python
g = str
print(g.__name__)
```

```
pxx:     Unhandled exception: AttributeError: 'type' object has no attribute '__name__'
CPython: str
```

Position-independent — the same error at top level, in a call argument, and as
a parameter default, which is what says it is the VALUE and not the context.

## The boundary

| case | result |
| --- | --- |
| `class W: pass` then `W.__name__` | **ok** — `W` |
| `g = W` then `g.__name__` | **ok** — `W` |
| `str.__name__` / `g = str; g.__name__` | **AttributeError** |
| `def f(c=str): c.__name__` | AttributeError (same cause, not the default path) |

So a USER class carries `__name__` and a BUILTIN type does not: the two are
different runtime values — a user class boxes as `VT_CLASSREF` (its RTTI blob,
which has the name), a builtin type as `VT_BTYPE` (a small type code), and only
the first has anywhere to read a name from.

## Fix shape (not attempted)

`VT_BTYPE`'s payload is the `PYBT_*` code, so `__name__` is a code→name table
lookup on the builtin-type attribute path — the same place `PyBoxBuiltinType`
values are read. Small, and worth checking `__qualname__` and `repr()` of a
builtin type at the same time, since they read from the same nothing.

## Why the priority is low

It fails LOUDLY with the right exception type, which is the dialect's stated
preference over a wrong value, and no corpus wall measured on 2026-08-17 is
blocked on it. It is a completeness gap, not a defect that misleads.

## Gate

`print(str.__name__)` prints `str`, matching CPython, and the user-class rows
above keep working.
