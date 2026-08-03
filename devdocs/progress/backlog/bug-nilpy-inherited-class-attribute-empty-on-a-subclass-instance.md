---
track: N
prio: 60
type: bug
summary: "`Sub().kind` reads empty/zero when `kind` is a class attribute declared on the BASE — construction copies only the class's OWN class attributes, never the inherited ones. Silent wrong value"
---

# An inherited class attribute is empty when read through a subclass instance

- **Type:** bug (NilPy class attributes — SILENT WRONG VALUE) — **Track N**
- **Found:** 2026-08-03, writing the gate for
  [[bug-nilpy-class-attribute-unreachable-through-the-class-name]].
  **Pre-existing** — reproduced on a baseline build of the parent commit, so it
  predates that fix and is not caused by it.

## Repro

```python
class Base:
    kind = "base"
class Sub(Base):
    pass
print(Sub().kind)       # CPython: base      pxx: (empty line)
print(Base().kind)      # CPython: base      pxx: base
```

An integer attribute reads `0` the same way. No diagnostic, no crash — the
instance simply carries a zeroed field.

## Cause

Construction copies class attributes into the new instance from two loops, and
BOTH are keyed on the class's own registrations:

- `PyClsAttrCi[i] = ci` — the folded-constant table, filtered to this class
- `UClsFBase[ci] .. UClsFCount[ci]` — this class's OWN field span

A subclass declares neither, so `Sub()` runs no class-attribute stores at all.
The FIELD is inherited (the layout continues the parent's, so the offset the
read uses is correct) — only the value was never written, which is exactly why
the failure is silent rather than a crash.

Both loops appear twice, in `PyConstructUClass`'s hoisted-temp form and in
`PyClassAttrInitSeq` (the constructor-head form) — they must be fixed together
or a class with a constructor and one without will disagree.

## Fix shape

Walk the parent chain, ROOT FIRST, in both emitters, so a subclass that
redeclares an attribute stores last and wins. The class-written attributes
introduced by the parent ticket are unaffected: they have no instance field and
resolve through `FindClassVar`, which already walks the parent chain — which is
why `Sub.kind` (through the class NAME) is correct today and only the instance
route is wrong.

## Gate

A `.npy` diffed against CPython: a base with literal, expression and container
class attributes read through a subclass instance; two levels of subclassing; a
subclass that redeclares one of them; a subclass with its own `__init__` (the
`PyClassAttrInitSeq` path) and one without (the hoisted-temp path); and the
existing class-attribute tests still green.
