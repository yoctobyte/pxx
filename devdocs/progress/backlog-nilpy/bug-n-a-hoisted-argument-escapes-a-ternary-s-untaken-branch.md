---
slug: bug-n-a-hoisted-argument-escapes-a-ternary-s-untaken-branch
title: a hoisted argument escapes a ternary's untaken branch
summary: >
  `f(*[track(10), track(20)]) if c else 99` with c False evaluates BOTH
  track() calls; CPython evaluates neither. The star machinery lowers its
  operand into hoisted statements (PyHoistStmt), and the hoist lands at the
  enclosing STATEMENT, not inside the conditional arm the call sits in -- so
  every construct in this frontend that hoists has the same escape. Found while
  deciding whether the run-time dynamic-dispatch path could route every arity
  through a hoisted TPyList; it cannot, and that decision is now documented in
  PyMakeDynMethCall as the reason the small arities keep their direct rungs.
  Fixing this is what would let those two paths merge.
track: N
type: bug
prio: 55
owner: unassigned
status: open
---

## Measured 2026-09-13, at `533c194fd`, no dynamic dispatch involved

```python
calls = []

def track(v):
    calls.append(v)
    return v

def f(a, b):
    return a + b

c = False
r = f(*[track(10), track(20)]) if c else 99
print(r, calls)
```

| | result |
| --- | --- |
| CPython | `99 []` |
| pxx | `99 [10, 20]` |

The VALUE is right in both. Only the side effects differ, which is why no
`expect_same` row over `r` could ever have caught it — the instrument has to be
a log of what RAN, not of what was returned. Same structural blindness as
CLAUDE.md's leak and store-order rows.

## Why it matters beyond a probe

Two callers pay for it today and both are ordinary Python:

- A star-unpacked call in a conditional expression — the row above.
- Any construct whose desugar hoists. `enumerate(xs, start=bump())` binds its
  start to a hidden local before the loop *deliberately* (once, not
  per-iteration), and that hoist is correct because a `for` header always runs.
  A hoist inside a ternary arm is the same mechanism where the arm may not.

## The shape of a fix, not yet chosen

The hoist target is the enclosing statement. A ternary arm is not a statement,
so either the hoisted setup moves into a generated `if` that mirrors the
ternary, or the ternary itself lowers to one. The second is the smaller change
and is what `AN_TERNARY`'s lowering would have to grow; the first duplicates the
condition.

Not attempted here: this was found as a CONSTRAINT on another change, measured,
and banked rather than microfixed.

## What is blocked on it

`PyMakeDynMethCall` runs two paths — direct `pydyn_meth<n>` rungs for four
arguments or fewer, a hoisted `TPyList` past that — and the split exists ONLY
because of this bug. Merge them when it is fixed; the comment there says so.
