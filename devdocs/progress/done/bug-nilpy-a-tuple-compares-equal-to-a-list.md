---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`(1, 2) == [1, 2]` answers True where CPython says False — pylist_eq compares by position without asking the FKind tag, so a tuple and a list of the same contents are indistinguishable to it. Same root cause as the set half, which is fixed; the tuple half was left because tightening it moves code paths that never set an explicit kind."
status: done
owner: claude-A-N
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

## DONE 2026-08-13 — the sweep this ticket asked for came back empty, so the guard is free

`(1, 2) == [1, 2]` is False, both ways round, and a tuple stays equal to a tuple.

This ticket existed because the set half of the same fix deliberately stopped
short: the set arm only fires for values explicitly built as sets, while a
tuple-vs-list guard fires for EVERY value whose `FKind` was never stamped, and
that population was unswept. So the work was the sweep, not the guard.

**Swept, and the population is empty.** Every constructor this ticket named to
check, plus the rest of the family, asked for `type(x).__name__` and compared
against CPython: `d.items()` elements, `zip`, `divmod`, `tuple()`, `list()`, a
slice of a tuple and of a list, concatenation of each, a list comprehension,
`sorted()`, and all three literals. Every one already agrees. There is nothing
that would start comparing unequal, so `if (a.FKind = PYSEQ_TUPLE) <> (b.FKind =
PYSEQ_TUPLE) then Exit` is one line and costs nothing.

### What would catch a guard that went too far

The rows where a tuple must still compare EQUAL, each reaching the comparison
from a different side: tuple-vs-tuple, a tuple as a dict KEY (hashed by
content — `d[(1, 2)]`, and a grid keyed by `(i, j)`), a tuple in a SET,
`.index()` / `.count()` over a list of tuples, a nested compare and `in`. All
match.

The seven existing tuple tests were re-run against their exact assertions,
including `test_nilpy_tuple_dict_key`, whose Makefile row diffs against live
CPython.

Test `test/test_nilpy_tuple_is_not_a_list.{npy,expected}` (`.expected` from
CPython), wired into `test-nilpy` — it carries the sweep as its second half, so
a future constructor that forgets to stamp its kind is caught by the same file
that licensed the guard.

`compiler/builtin/**` change, so it carries the stabilize+pin obligation.
Gate: self-host fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
