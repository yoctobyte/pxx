---
track: N
prio: 62
type: bug
owner: unassigned
blocked-by: []
summary: "`self.v = 2.5` in a SUBCLASS, where `v` was declared `self.v = 1` in the parent, prints 4612811918334230528 — the double's bits. The sibling defect within one class was fixed 2026-08-27; this one is left because the parent's layout is already final by the time the subclass is registered, so it needs a whole-program pre-pass rather than a local join."
---

# A field declared in an ancestor is not widened by a descendant's rebind

- **Type:** bug (Track N) — **silent wrong value**, the expensive class.
- **Filed:** 2026-08-27 while resolving
  [[bug-n-a-fields-type-is-fixed-by-its-first-assignment-and-never-widened]],
  whose fix covers the within-one-class case and deliberately stops here.
- **Measured on:** pinned **v383** (`18392d1d3181`) and HEAD alike — the sibling
  fix changed neither row.

## Repro

```python
class P:
    def __init__(self):
        self.v = 1
class Q(P):
    def widen(self):
        self.v = 2.5
        return self.v
print(Q().widen())
```

| | |
| --- | --- |
| CPython | `2.5` |
| pxx | `4612811918334230528` — the double's BITS read as an integer |

Same shape through a base class used as a mixin-style helper:

```python
class M:
    def setup(self):
        self.m = 1
class C(M):
    def __init__(self):
        self.setup()
    def widen(self):
        self.m = 3.5
        return self.m          # CPython 3.5, pxx 4615063718147915776
```

`C(M)` is ordinary single inheritance — the FIRST base stays a real parent and
is not flattened — so this is the same case, not a mixin-specific one.

## Why the sibling fix stops short of it

`PyRegisterClassMembers` now widens a re-assigned field with `PyWidenBinding`
and re-lays-out the class's own window. It is restricted to **that window on
purpose**: a field found by `FindUField` in a descendant may belong to an
ancestor, and rewriting it there changes a layout that is already final —
`curOff` for every subclass starts at `UClsSize_[parent]`, so any subclass
registered *before* this one already baked in the narrow size. Widening the
parent in place would silently corrupt those.

So the answer is not a wider guard, it is a different phase: the join has to be
computed over **every** class body that assigns the name, before any class in
the hierarchy is laid out. That is a whole-program pre-pass, and it is the same
shape as the ordering hazard the sibling ticket flagged, one level up.

## Note on correctness, not just layout

Widening the ancestor is the *right* answer and not merely the convenient one: a
`P`-typed reference can point at a `Q`, so if any descendant stores a float in
`v`, the slot must hold a float for every `P`. A fix that widened only the
descendant's view would put two different types on one slot.

## Gate

The two repros above match CPython, plus the controls the sibling ticket's test
already carries (a same-type rebind must not widen; neighbouring fields keep
their values), plus one new control: two subclasses of the same parent, one of
which widens, and the other still reading the field correctly.
