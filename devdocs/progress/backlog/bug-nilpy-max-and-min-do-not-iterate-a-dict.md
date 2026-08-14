---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`max(d)` / `min(d)` over a DICT raise `TypeError: max() argument is not iterable`; CPython answers the largest/smallest KEY. Every other iterable works, and `sorted(d)` over the same dict already does the right thing."
---

# max()/min() do not iterate a dict

```python
print(max({"k": 1, "z": 2}))     # CPython: z      pxx: TypeError: max() argument is not iterable
```

Found 2026-08-14 while adding `max(xs, default=D)`
([[bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep]] item 4) — the
`default=` row for a dict raised, and the raise turned out to have nothing to do
with `default=`: plain `max(d)` does it too.

## Why it is worth fixing rather than documenting

Iterating a dict yields its KEYS everywhere else in this frontend — `for k in d`,
`list(d)`, `sorted(d)` and `in` all agree with CPython. `max`/`min` are the
outliers, so this is an inconsistency inside NilPy, not a deliberate divergence.

`sorted` is the precedent to copy: it grew a dict overload
(`sorted(d: TPyDict; key; reverse)`) that delegates to the list form over
`keylist`, so the ordering logic stays in one place. `max`/`min` want the same
one-line delegation.

## Failure mode

A loud TypeError, which is the good case — no silent wrong value.

## Gate

A `.npy` diffed against CPython: `max(d)`, `min(d)`, both with `default=` on an
empty dict and a populated one, and `max(d, key=d.get)` if that resolves.
