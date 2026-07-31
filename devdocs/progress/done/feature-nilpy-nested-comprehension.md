---
summary: "nilpy: a comprehension INSIDE another comprehension's expression"
type: feature
track: N
prio: 60
---

# nilpy: nested comprehensions

- **Type:** feature (Nil-Python frontend) — **Track N**
- **Opened:** 2026-07-27, walking songformatter's `key_analysis.py`
  ([[feature-demo-songformatter-pxx-target]]).

## Repro

```python
ks = ["ab", "cd"]
d = {k: [c for c in k] for k in ks}     # error near: c for c  k >>> for k
e = [[c for c in k] for k in ks]        # same
```

songformatter, `key_analysis.py:194`:

```python
major_scales = {key: [ALL_NOTES[p] for p in _scale_pitch_classes(key)] for key in MAJOR_KEYS}
```
-> `undefined variable (key)`.

## Cause (as far as it was chased)

A comprehension desugars to a hidden temp plus a loop, and the loop's BODY is
built by re-parsing the element expression from `PyCompExprStart`. That much
would handle nesting on its own — the inner comprehension is re-parsed at a point
where the outer loop variable is in scope.

The problem is HOISTING. The inner comprehension's own setup goes through
`PyHoistStmt`, which pushes statements out to the enclosing STATEMENT, i.e. in
front of the outer loop — where the outer loop variable does not exist yet. Hence
"undefined variable (key)": the inner loop's `in _scale_pitch_classes(key)` is
evaluated before `key` is bound.

## Shape

The hoist target has to be the enclosing comprehension's loop BODY, not the
enclosing statement, whenever one comprehension is built inside another's element
expression. That is a hoist-stack rather than a single `PyHoistHead` — push a new
head when a comprehension body starts building, pop it when the body is closed,
and let PyHoistStmt land on the innermost one.

## Gate

`make test-nilpy` green with a `.npy` case covering a list-in-list and a
list-in-dict comprehension, both diffed against CPython, + `--tier quick` +
self-host byte-identical.

## Why it matters

It is the last known wall in `key_analysis.py` (the module has cleared a dozen
already), and dict-of-list comprehensions are ordinary Python — this will show up
again in any real corpus.

## Log
- 2026-07-31 — resolved, commit b30f724e8.
