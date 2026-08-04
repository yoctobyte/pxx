---
track: N
prio: 30
type: bug
summary: "repr() is not a builtin at all, and sum(range(n)) fails 'undefined variable (range)' because range is only a for-header form"
status: done
owner: claude-AN
---

# `repr()` and `sum(range(...))` are undefined variables

```python
i = 5
print(repr(i))          # CPython: 5    pxx: error: undefined variable (repr)
print(sum(range(i)))    # CPython: 10   pxx: error: undefined variable (range)
```

Both found by the promo output-diff sweep
([[task-n-enumerate-the-promo-surface-by-output-diff]]) and both **independent
of promotable ints** — they reproduce with an ordinary `tyInteger` argument.
Filed together because they are one shape: a builtin that exists in the runtime
but is not reachable from the place the program used it.

## `repr`

`pyrepr_of` already exists in pylib with the full per-type overload set (it is
what an f-string's `!r` hole lowers to). Only the user-facing `repr()` name has
no frontend arm, so it never resolves.

## `sum(range(...))`

NilPy's `range` is not a value: it exists as the counted-loop lowering in a
`for` header, plus a materialising path (`PyParseRangeList`) gated on the
enclosing call being literally `list(`. So `list(range(3))` works and
`sum(range(3))` does not.

The gate is `PyRangeAsListWanted`, which peeks at the enclosing callee name.
Widening it beyond `list` is the obvious fix; `sum`, `max`, `min`, `sorted`,
`tuple` and `set` all take an iterable and all currently fail the same way.
Worth checking whether the enclosing-name whitelist should instead become
"any call argument position", since the lazy-vs-materialised distinction is
only observable for `print(range(3))`.

## Gate

Per-fix loop, plus a `.npy` test with each wrapper over `range` diffed against
CPython. `ls test/ | grep -E 'range|repr'` before creating a file.

## Log
- 2026-08-04 — resolved, commit PENDING-COMMIT.
