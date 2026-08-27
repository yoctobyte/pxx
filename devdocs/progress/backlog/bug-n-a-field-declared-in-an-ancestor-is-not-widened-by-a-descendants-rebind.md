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

## Scoping note — 2026-08-27 (still open; re-measured, not fixed)

Both repros reproduce unchanged at HEAD (`22690b507548`, pin v386), plus the
third control the Gate asks for:

```
Q().widen()   4612811918334230528     CPython 2.5
R().read()    1                       CPython 1     <- the sibling subclass is fine
P().v         1                       CPython 1
```

**The whole-program pre-pass this ticket calls for already EXISTS.**
`PyRegisterClassFieldsPrepass` (pyparser.inc) walks the entire token stream
before any class is parsed, finds every `class` header, computes each body span
with `PyFindBodyEnd`, and calls `PyRegisterClassMembers` for all of them. It
already runs *two* sub-passes over that stream — the first only to mark which
classes are used as a second base. So the shape the fix needs is not new
machinery; it is a **third sub-pass inserted before the registering one**, which
computes per (class, field-name) the join over that class and every descendant,
into a side table `PyRegisterClassMembers` consults when it first sizes a field.
That is where to start, and it is a much smaller starting position than "a whole
new phase".

**Two things block it, and both are worth knowing before anyone opens the file:**

1. **The field TYPE inference is not callable.** The `tk` the widening site
   (pyparser.inc, the `else if (fi >= UClsFBase[ci])` arm) joins against is
   computed inline, deep inside `PyRegisterClassMembers`'s ~1200-line body, from
   surrounding context. A detect sub-pass needs the same answer, and writing a
   second inference is precisely the third-spelling failure
   `devdocs/dev/normalise-dont-special-case.md` warns about — the copy that
   stays broken. So step one is **extracting that inference into a routine**,
   behaviour-preserving, exactly as `PyJoinInferTk` was extracted from the
   conditional-expression arm for
   [[bug-n-a-short-circuit-or-returning-self-is-typed-as-a-number]]. Do that as
   its own commit and gate it before touching layout at all.

2. **The pre-pass does not lay out every class.** It falls back to fields-only
   when a base cannot be resolved yet ("If the base cannot be resolved yet, fall
   back to fields-only and let PyParseClass do the full run as before"), and
   skips classes used as mixins. So a side table must be consulted by BOTH
   registration routes, not just the pre-pass one, or the fix works for most
   programs and silently does not for the rest — the worst available outcome
   for a bug whose symptom is already a silent wrong value.

**One thing that looked like a shortcut and is not.** A tempting cheaper fix is
to widen the ancestor in place when a descendant is registered, and re-lay-out
the already-registered descendants — attractive because in the pre-pass no
method BODY has been compiled yet, so no emitted code is stale. It fails on
point 2: the classes that took the fields-only fallback get their real layout
later, from `PyParseClass`, by which time other bodies are being compiled. Do
not take it.

Parked deliberately rather than microfixed. `root-cause-over-microfix.md`: the
diagnosis is the deliverable when the session cannot finish the overhaul, and a
narrow "widen when the RHS is a float literal" patch would close the two repros
above while leaving the concept wrong and the ticket looking done.
