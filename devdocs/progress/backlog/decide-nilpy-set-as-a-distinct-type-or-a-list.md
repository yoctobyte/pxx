---
track: U
prio: 55
type: decision
summary: "pxx backs a Python set with TPyList. That makes set difference work, makes `list - list` unrejectable, and makes a set repr as [1, 3] instead of {1, 3}. Give sets their own row, or keep the alias and pay at run time?"
---

# Decide: does a Python `set` get its own type, or stay a `TPyList`?

- **Type:** decision (Track U) — escalated rather than guessed
- **Opened:** 2026-08-02, from the narrowed remains of
  [[bug-nilpy-same-kind-undefined-operators-still-compute]] after its table was
  re-measured. Also the root of [[bug-nilpy-set-is-a-list-not-a-set]].

## The fork

A Python `set` is represented by `TPyList` — the same row as a list. One
representation, three consequences, all measured:

1. **`set([1,2,3]) - set([2])` works** and must keep working. Good.
2. **`[1] - [2]` returns `[1]`** where CPython raises `TypeError`. The static
   "this operator pair is undefined" rule cannot fire on `list - list`, because
   it cannot tell a list from a set. This is the single row left open on that
   ticket.
3. **A set prints as `[1, 3]`**, where CPython prints `{1, 3}`. Same cause: the
   repr is chosen from the row.

Point 1 is why the alias exists; points 2 and 3 are what it costs. The cost is
paid in the currency this repo cares most about — a silent wrong value (2) and a
visibly wrong output (3).

## Options

**A. Give sets their own row (`TPySet`, or a flag on the rec).**
- Fixes 2 and 3 together, and makes `list - list` rejectable by the same
  table-driven rule the differing-kind half already uses.
- Set semantics become expressible for real (uniqueness on insert, `in` by hash
  rather than scan, `|`/`&`/`^`).
- Touches construction, printing, and every place that currently treats a set as
  a list. The largest change of the three.

**B. Keep the alias; add a runtime kind check on the same-kind operator path.**
- Cheaper, keeps set difference working, fixes 2 only.
- Costs a call on a path that is currently pure arithmetic, and leaves the repr
  wrong.

**C. Leave it.**
- `[1] - [2]` stays a silent wrong value and a set keeps printing as a list.
  Recorded for completeness; hard to defend given how ordinary both spellings
  are.

## Recommendation

**A.** It is the only option that addresses the cause rather than a symptom, it
retires two tickets at once, and set semantics (uniqueness, hashing) are
otherwise unreachable — today a NilPy `set` is a list wearing the name, so
`len(set([1,1]))` and `x in set(...)` are wrong or slow in ways nobody has
measured yet. B is the honest fallback if the layout work is unwelcome now; it
should be chosen knowing the repr stays wrong.

## What is NOT being asked

Whether the differing-kind static rejection stays — it does, it is correct and
landed. This is only about the same-KIND case, which is undecidable while one
row means two types.

## Unblocks

- [[bug-nilpy-same-kind-undefined-operators-still-compute]] (its last row)
- [[bug-nilpy-set-is-a-list-not-a-set]]


## 2026-08-06 — a FOURTH consequence, and user direction on the typing half

Measured while sweeping `isinstance`: the shared row also makes **list, tuple
and set mutually indistinguishable to `isinstance`**, and a set reports
`type(x).__name__ == 'list'`.

```
value    CPython                 pxx
[1,2]    list,  name 'list'      list + tuple, name 'list'
(1,2)    tuple, name 'tuple'     list + tuple, name 'tuple'
{1,2}    neither, name 'set'     list + tuple, name 'list'
```

`dict`, `str`, `int`, `float`, `bool` and `None` are all exact — the damage is
confined to the three kinds on this row. Filed as
[[bug-nilpy-list-tuple-and-set-are-indistinguishable-to-isinstance]] (prio 70).

This is worse than consequences 2 and 3 in reach: `isinstance(x, list)` is how
an ordinary library accepts several container kinds through one parameter and
tells them apart inside, so it hits normal third-party-shaped code rather than
an unusual spelling.

**User direction on this half** (2026-08-06): *"need to tag original type so we
can't confuse lists from tuples"*. That is not the whole of this decision — it
does not settle the set's `repr` (`{1, 3}` vs `[1, 3]`) or whether `[1] - [2]`
should raise — but it does pick the mechanism, and it is the cheap end of
**option A**: a kind tag on the instance rather than a separate `TPySet` row.

Relevant to costing option A: `TPyList` **already carries `FIsTuple: Boolean`**,
maintained at every tuple-producing site and already consumed by
`pytype_name_v`. Widening that one field to a three-valued kind is most of what
option A needs for the typing half, and it fixes the set's type NAME for free.
The repr and operator-rejection halves can then key off the same field whenever
this decision is taken.
