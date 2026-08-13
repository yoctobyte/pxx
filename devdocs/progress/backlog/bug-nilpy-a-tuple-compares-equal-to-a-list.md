---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`(1, 2) == [1, 2]` answers True where CPython says False — pylist_eq compares by position without asking the FKind tag, so a tuple and a list of the same contents are indistinguishable to it. Same root cause as the set half, which is fixed; the tuple half was left because tightening it moves code paths that never set an explicit kind."
---

# A tuple compares equal to a list

```python
print((1, 2) == [1, 2])    # CPython False — pxx True
print([1, 2] == (1, 2))    # CPython False — pxx True
```

## Same root cause as the set half, deliberately not fixed with it

A tuple, a list and a set are all one `TPyList` here, told apart by `FKind`
(PYSEQ_LIST / PYSEQ_TUPLE / PYSEQ_SET). `pylist_eq` now consults that tag for
the SET case — a set compares by membership and is never equal to a sequence
([[feature-nilpy-set-needs-runtime-tag-for-display-and-equality]]) — and the
one-line generalisation is to refuse ANY kind mismatch.

It was not done in that pass on purpose: the set arm only fires for values that
were explicitly built as sets, while a kind mismatch between tuple and list
fires for every value whose kind was left at its default. Anything that
constructs a tuple-shaped result without stamping PYSEQ_TUPLE — or a list
without stamping PYSEQ_LIST — would start comparing unequal, and that surface
was not swept.

## Shape of the fix

In `pylist_eq`, replace the set-only guard with `if a.FKind <> b.FKind then
Exit` — then FIND the constructors that leave the kind unset. `d.items()`
(pairs), `zip`, `divmod`, a multiple-return, and comprehension results are the
places to check first: each yields something Python calls a tuple.

## Gate

A `.npy` diffed against CPython covering tuple-vs-list both ways, tuple-vs-tuple
and list-vs-list as controls, and the constructors above compared against a
literal of the kind CPython says they are.
