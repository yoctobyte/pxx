---
prio: 30
track: N
type: bug
blocked-by: []
---

# `@dataclass(order=True)` does not parse — the decorator takes no arguments

- **Type:** bug (loud: a parse error, not a wrong answer) — **Track N**
- **Found:** 2026-08-08, while gating
  [[bug-nilpy-list-sort-ignores-lt-dunder-on-objects]] (it was going to be the
  natural third case in that test)
- **Owner:** —

```python
from dataclasses import dataclass

@dataclass(order=True)
class D:
    v: int

print(sorted([D(3), D(1)]))      # CPython: [D(v=1), D(v=3)]
```

```
pascal26:20: error: unexpected token
  near:     dataclass  >>> order
```

The bare `@dataclass` form works. Only the CALLED form is rejected, so the
decorator parser evidently accepts a bare name and no argument list.

## Scope

CPython's `dataclass()` takes `init`, `repr`, `eq`, `order`, `unsafe_hash`,
`frozen`, `match_args`, `kw_only`, `slots`, `weakref_slot`. They are not all
equally urgent — `order=True` and `frozen=True` are the ones real code reaches
for, and `eq=False` is the one that would interact with the newly-added
`__eq__` dispatch.

A useful first step is **parsing the argument list and honouring only what is
implementable, rejecting the rest explicitly by name.** Accepting and silently
ignoring `frozen=True` would be worse than the current parse error: the class
would look immutable and not be, which is a silent wrong answer where today's
failure is loud. `order=True` is the one with an obvious lowering now that
`sorted()` dispatches `__lt__` at run time — generate the comparison dunders
over the field tuple, exactly as CPython documents.

## Why prio 30

The error is loud and the workaround is one hand-written `__lt__`, which is
what the new `test_nilpy_sort_lt_dunder` uses. It blocks no corpus today.

## Gate

A `.npy` diffed against CPython covering `@dataclass(order=True)` sorting, and
an explicit named rejection for each option NOT implemented — with a test that
the rejection is a compile error rather than silence.
