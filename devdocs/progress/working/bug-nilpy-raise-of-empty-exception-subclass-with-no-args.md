---
track: N
prio: 65
type: bug
summary: "`raise E()` where E is a user Exception subclass with an EMPTY body segfaults or prints nothing. Passing any argument, or giving E an __init__, makes it work — so the idiomatic empty exception class is the broken one"
status: working
owner: claude-AN
---

# `raise E()` on an empty Exception subclass: segfault / silent no-op

- **Type:** bug (NilPy exceptions — SEGFAULT or SILENT) — **Track N**
- **Found:** 2026-08-02, while testing one-line class bodies
  ([[bug-nilpy-one-line-def-and-class-bodies-do-not-parse]]). **Pre-existing and
  unrelated to that work** — it reproduces on the ordinary indented spelling.

## Repro

```python
class E(Exception):
    pass

try:
    raise E()
except E:
    print("caught")        # CPython: caught     pxx: nothing, or a segfault
```

## The controls narrow it to one shape

| variation | result |
| --- | --- |
| `raise E("m")` — any argument | **caught** |
| `E` given an `__init__` | **caught** |
| `raise Exception("m")` — the base class | **caught** |
| **`raise E()` with `class E(Exception): pass`** | **segfault / nothing** |

So it needs the subclass to have NO constructor AND the raise to pass NO
argument. Both halves of that are the idiomatic spelling — an empty exception
class is the standard way to declare a domain error, and raising it bare is the
standard way to use one.

## Why it matters more than the repro suggests

The `except` clause never runs, so control does not merely produce a wrong
value — it takes a wrong PATH. A program using a bare sentinel exception for
flow control silently does not handle it. And the two moods (segfault vs silent)
mean a test suite may see it as either a crash or a missing line.

## Where to look

The generated constructor for a user Exception subclass with no `__init__` and
no fields. `raise E("m")` working suggests the message-carrying path is fine and
the no-argument path either skips construction or hands `raise` something
unconstructed. Check what `E()` lowers to when the class has no ctor and no
fields — the class-attribute work of 2026-08-02 showed that an EMPTY member set
is its own edge case in this pre-pass family.

Reach for `-dPXX_HEAP_DEBUG` and `-dPXX_OBJTRACE` before print-bisecting: an
unstable segfault/silence pair is the signature of reading something that was
never initialised.

## Gate

A `.npy` diffed against CPython: bare `raise E()` for an empty subclass, caught
by its own name and by `except Exception`; the same with an argument; an empty
subclass raised and NOT caught (the traceback path); a subclass with `__init__`;
two sibling empty subclasses distinguished by their `except` clauses; and the
one-line `class E(Exception): pass` spelling of each.
