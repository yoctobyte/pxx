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

## DECIDED 2026-08-04 (Rene) — option 1: keep the snapshot, document it

> "we are handling it correct. code that works with cpython will work with pxx.
> if a programmer decides to delete keys it's iterating he/she deserves an
> error… i think this is 'good enough'. we could consider a 'strict' mode for
> python that tosses a runtime error, at the cost of overhead. totally worth
> documenting this all."

One correction was made to the framing before it was written down, because it
would otherwise have been documented wrongly: **it is not "the same failure with
a different message"**. Measured, only one of the three shapes errors at all —
an insert completes silently, and a delete whose key the body never re-reads
completes AND still visits the deleted key. Only a delete-then-read raises
(`KeyError`). The decision stands regardless: every program that can tell the
difference is one CPython rejects, so no working Python program is affected.

**A `--strict-python` mode remains an open option**, explicitly not rejected —
recorded here rather than dropped, since the per-iteration cost is only
unacceptable as a default.

### Deliverables, all landed

- `devdocs/dev/nilpy-semantics-divergences.md` — a new file, since no doc listed
  language-level deliberate divergences (the compat-tiers doc is about library
  naming). Carries the three measured rows, the reason the divergence is
  acceptable, the strict-mode option, and the precedents **checked rather than
  assumed**: Go and JavaScript `Map` are the permissive camp, while C# and Java
  are the strict ones that throw — so C# is not the example it looks like. And
  the honest part: neither Go nor JS *snapshots*, so pxx alone will produce a
  removed key.
- The same file records that **list iteration is NOT a divergence** — it matches
  CPython exactly, both growing and shrinking. CPython is itself asymmetric, and
  the note exists so nobody "fixes" the list for consistency with the dict.
- `test/test_nilpy_dict_mutation_during_iteration.npy` + `.expected`, wired into
  `make test-nilpy`, pinning all three shapes with a header stating outright that
  the expectations are deliberately NOT CPython's and must not be "corrected".

### Checked, as asked: no FAIL test detects this

Searched for a test asserting the CPython behaviour — there is none, and no
`*_fail` test covers it. `test/test_nilpy_iterate_live_list.npy` contains a dict
loop, but only as a NON-mutating control, so it needed no change.

Moved to `decided/`.
