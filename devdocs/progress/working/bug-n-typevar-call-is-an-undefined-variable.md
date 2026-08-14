---
track: N
prio: 55
type: bug
summary: "`MessageT = TypeVar(\"MessageT\")` at module scope dies with `undefined variable (TypeVar)`: `typing` is a consumed-and-ignored import, so the names it exports that have a RUN-TIME call form — TypeVar, Generic, NewType, cast — are bound to nothing. The largest remaining language gap in the neuzelaar census once unreadable annotations stopped refusing modules."
status: working
owner: agent-AN
---

# `TypeVar(...)` is an undefined variable

- **Type:** bug (upward-compatibility violation) — **Track N**.
- **Found:** 2026-08-14, in the census re-run after
  [[bug-n-an-uninterpretable-annotation-refuses-the-program]] landed and the
  files that used to die at an annotation reached their `TypeVar` line instead.

## Reproduce

```python
from typing import TypeVar
MessageT = TypeVar("MessageT")
print("ok")
```

```
error: undefined variable (TypeVar)
```

## Why

`typing` is on `PyImportRootIsConsumedOnly` — the from-import is consumed and
dropped, on the reasoning that what it exports is "a compile-time annotation with
no run-time existence, or an ordinary pylib symbol already in scope". That is
true of `List`, `Optional`, `Dict` and friends, which only ever appear inside
annotations and are read by `PyAnnTypeAt`, never evaluated.

It is **not** true of the handful of typing names that are CALLED at run time:
`TypeVar`, `NewType`, `Generic`, `cast`, `overload`. Those appear in ordinary
statement position, so consuming the import leaves the name unbound and the
program fails at the call, naming `TypeVar` rather than the import that dropped
it — the exact "silently dropping an import is the worst shape a gap can take"
failure the consumed-only list's own note warns about, arrived at from the other
direction.

## What the answer probably is

NilPy erases generics, and after
[[bug-n-an-uninterpretable-annotation-refuses-the-program]] the resulting name is
only ever *used* in annotations, which now degrade to Any. So the value a
`TypeVar` call produces never has to be anything in particular — binding it to a
harmless object (its own name string, say) makes every observed use work.

`cast(T, x)` is the one that carries real semantics and they are trivial:
CPython's `cast` returns its second argument unchanged.

Scope `Generic[...]` as a base class explicitly — `class Bus(Generic[MessageT])`
is a different site (a base-class list, not a call) and should not be assumed to
fall out.

## Measured

21 of 168 git-tracked neuzelaar files fail with `undefined variable`, the largest
remaining language gap; `TypeVar` is the leading single cause. Recipe:
`devdocs/dev/python-libraries.md` §7 — regenerate rather than trusting this
number.
