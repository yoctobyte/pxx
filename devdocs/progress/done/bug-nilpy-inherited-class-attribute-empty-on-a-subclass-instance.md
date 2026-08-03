---
track: N
prio: 60
type: bug
summary: "`Sub().kind` reads empty/zero when `kind` is a class attribute declared on the BASE — construction copies only the class's OWN class attributes, never the inherited ones. Silent wrong value"
status: done
owner: claude-AN
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

## Resolved 2026-08-03

Both emitters now walk the ancestor chain ROOT FIRST, via a `PyClassDepth` /
`PyClassAncestorAt` pair rather than a shared array — the walk is quadratic in
the chain depth, which is free, and not sharing a buffer is what keeps the two
routines independent. Root-first is the whole ordering rule: a subclass that
redeclares an attribute stores last and its value is the one the instance keeps.

Two details the fix turns on:

- the hidden global is named after the DECLARING class, so the field loop is
  driven by each ancestor's OWN field span (`UClsFBase[cur]`) while the field's
  type and the receiver stay the subclass's. `FindUField` already walked the
  chain, which is exactly why the field existed and only its value did not.
- the two emitters had to change together. A class with a constructor takes
  `PyClassAttrInitSeq` and one without takes the hoisted-temp form; fixing one
  would have made two arrangements of the same class disagree.

`test/test_nilpy_inherited_class_attribute.npy` (+ `.expected`, wired into
`make test-nilpy`), byte-identical to CPython: one and two levels of
subclassing; a subclass redeclaring an inherited attribute; literal, expression
and container initialisers; a subclass with its own `__init__` (the
constructor-head route) and one without (the hoisted route); an `__init__` that
overwrites an inherited class attribute, which must still win because it runs
after; and a class-written attribute incremented from a subclass constructor as
a control that the shared-slot row and inheritance agree.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical.

## Log
- 2026-08-03 — resolved.
- 2026-08-03 — resolved, commit HEAD.
