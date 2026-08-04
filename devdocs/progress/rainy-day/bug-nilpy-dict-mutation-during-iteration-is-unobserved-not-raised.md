---
track: N
prio: 35
type: bug
blocked-by: decide-nilpy-dict-mutation-during-iteration
summary: "Mutating a dict while iterating it is silently unobserved; CPython raises RuntimeError 'dictionary changed size during iteration'"
---

# Mutating a dict during iteration is silently ignored

- **Type:** bug / divergence (NilPy) — **Track N**
- **Found:** 2026-08-02, while fixing
  [[bug-nilpy-for-in-snapshots-the-length-so-mutation-during-iteration-diverges]]
  (the LIST half, fixed in `4eadf7f54`). Noted in the code at the fix site.

```python
d = {"a": 1, "b": 2}
for k in d:
    d["c"] = 3
print(len(d))
```

CPython raises `RuntimeError: dictionary changed size during iteration`. NilPy
runs the loop to completion over the ORIGINAL keys and prints the new length.

## Why it happens, and why the list fix did not change it

`for k in d` does not iterate the dict. The frontend rewrites it to
`d.keylist()` — a snapshot COPY — and then iterates that list (`ci := listCi`
right after the keylist call in `PyParseForIn`). So the loop can never see a
concurrent mutation, and making the loop bound live for lists left this
untouched, because the live count now reads the copy.

## The divergence is real but mild

It is silent, which normally makes it high priority here. It is prio 35 anyway
because the program CPython would reject is one that is already relying on
undefined-ish behaviour, and NilPy's answer — iterate the keys as they were at
loop entry — is the *defensible* one that several languages choose. The cost of
matching CPython is a modification counter on TPyDict checked each iteration.

**This is a Track U question as much as a bug**: do we raise (CPython parity) or
keep the snapshot (defensible, and arguably nicer)? If the answer is "keep the
snapshot", this ticket becomes a documentation item rather than a fix, and the
behaviour should be stated explicitly rather than left as an accident of the
keylist rewrite. Recommendation: keep the snapshot, document it, and close —
raising costs a per-iteration check on every dict loop to reject programs that
are already broken.

## Gate

Whichever way it is decided, a `.npy` pinning the chosen behaviour, plus a note
in the NilPy semantics doc alongside the other deliberate
[[project_nilpy_semantics_vs_pascal_shared_layers]] splits.


## 2026-08-04 — escalated, not decided here

This ticket says "this is a Track U question as much as a bug" and then sits in
a bug queue where nobody can answer it. Filed as
[[decide-nilpy-dict-mutation-during-iteration]] with the three options (keep the
snapshot and document it; match CPython with a modification counter; match it
only under a strict flag) and this ticket's own recommendation carried across.

Also carried across, because it is the part most likely to read as a bug later:
the LIST half is already settled the OTHER way — a list loop's bound is LIVE
since `4eadf7f54`, so `for x in xs` DOES observe mutation. Whichever way the
dict goes, the asymmetry needs to be written down as chosen.

`blocked-by` set; no code touched.

## 2026-08-04 — DECIDED as intended behaviour; postponed

[[decide-nilpy-dict-mutation-during-iteration]] resolved: keep the snapshot,
document it. So this is no longer a bug — it is
`devdocs/dev/nilpy-semantics-divergences.md`, pinned by
`test/test_nilpy_dict_mutation_during_iteration.npy`.

What remains is the OPTIONAL half the decision explicitly kept open: a
`--strict-python` mode that raises `RuntimeError` on the modification, paying a
per-iteration check to buy CPython parity for the differential sweeps. That is a
feature nobody needs yet, so it moves to `rainy-day/` rather than staying in a
bug queue.

The measured correction that went with the decision, worth keeping here too: it
is NOT "the same failure with a different message". Only a delete-then-read
raises; an insert, and a delete whose key is never re-read, both complete
silently — and the latter still visits the deleted key.
