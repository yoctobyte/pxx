---
track: U
prio: 35
type: decide
---

# Raise on dict mutation during iteration, or keep the snapshot?

Escalated 2026-08-04 from
[[bug-nilpy-dict-mutation-during-iteration-is-unobserved-not-raised]], which
says outright "this is a Track U question as much as a bug" and then has to sit
in a bug queue where nobody can answer it. Filed here so it can be.

```python
d = {"a": 1, "b": 2}
for k in d:
    d["c"] = 3
print(len(d))
```

CPython raises `RuntimeError: dictionary changed size during iteration`. NilPy
runs to completion over the keys as they were at loop entry and prints the new
length — because `for k in d` is rewritten to iterate `d.keylist()`, a snapshot
COPY, so the loop cannot see a concurrent mutation at all.

## The fork

1. **Keep the snapshot, and DOCUMENT it** as a deliberate split rather than an
   accident of the keylist rewrite. Costs nothing at run time. The program
   CPython rejects is one already relying on undefined-ish behaviour, and
   "iterate the keys as they were at entry" is the answer several languages
   choose deliberately.
2. **Match CPython** — a modification counter on `TPyDict`, bumped on insert and
   delete, checked once per iteration, raising `RuntimeError`. Costs a
   per-iteration check on **every** dict loop in every program, to reject
   programs that are already broken.
3. Match CPython **only under a strict flag**, snapshot by default. Keeps the
   default free and makes parity available to the differential sweeps, at the
   cost of one more dialect switch.

**The bug ticket recommends 1**, and this ticket does not disagree — the point
of filing it is that "keep the current behaviour and write it down" is a
decision with a doc deliverable, not a no-op, and it should be made rather than
defaulted into.

Whichever way it goes, the deliverable is the same shape: a `.npy` pinning the
chosen behaviour and a line in the NilPy semantics notes beside the other
deliberate splits ([[project_nilpy_semantics_vs_pascal_shared_layers]]).

Note the LIST half of this question is already settled the other way: the loop
bound for a list is LIVE (`4eadf7f54`), so `for x in xs` DOES observe mutation.
Deciding 1 here means the two containers differ on purpose, which is itself
worth stating in the docs — it is the kind of asymmetry that reads as a bug
later if nobody wrote down that it was chosen.
