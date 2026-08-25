---
track: N
prio: 12
type: bug
blocked-by: []
summary: "`delattr`, `globals()` and `locals()` are `undefined variable`. delattr is a real gap with no runtime entry behind it; globals/locals want a run-time name table this dialect deliberately does not build, so they may be a documented divergence rather than a bug."
---

# `delattr`, `globals`, `locals`

Measured 2026-08-15 by sweeping the builtin surface one name per program, the
same pass that found [[bug-nilpy-setattr-is-absent]] (fixed). All three fail
LOUDLY at compile time as `undefined variable`, so nothing here is a silent
wrong answer.

## `delattr(o, name)` — a real gap

The completion of the attribute trio's write side. `setattr` now writes through
`pydynattr_set`/`_v`; there is **no `pydynattr_del`** to call, so this needs a
runtime entry as well as a frontend arm. Note the neighbouring refusal in
`pyvar_delitem`, which declines `del v[k]` on a user object for the same reason
— a dispatcher that does not exist yet — and says so loudly rather than
silently doing nothing. Same trade applies.

Worth doing together with `del o.attr`, if that turns out to be absent too:
measure it before assuming.

## `globals()` / `locals()` — probably a divergence, not a bug

Both want a run-time name table mapping source names to storage. NilPy compiles
locals to stack slots, and `exec(src)` with no namespace is ALREADY refused by
name for exactly this reason, with a message that explains it and points at the
explicit-dict form. `globals()` is the more tractable half (module-level names
do have storage), but a dict that does not write through is worse than no dict
at all — a `globals()["x"] = 1` that silently does nothing is the failure mode
this project refuses.

**Escalate rather than guess** if either is wanted: it is a
`devdocs/dev/nilpy-semantics-divergences.md` entry or a Track U `decide-*`, not
a quiet implementation choice.

## Gate

Per name as it lands: a `.npy` diffed against CPython, plus a row asserting a
user `def delattr` still shadows the builtin.
