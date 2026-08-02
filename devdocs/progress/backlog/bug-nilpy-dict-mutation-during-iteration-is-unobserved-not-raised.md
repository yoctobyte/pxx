---
track: N
prio: 35
type: bug
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
