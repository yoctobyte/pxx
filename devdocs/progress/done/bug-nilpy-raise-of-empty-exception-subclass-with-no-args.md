---
track: N
prio: 65
type: bug
summary: "`raise E()` where E is a user Exception subclass with an EMPTY body segfaults or prints nothing. Passing any argument, or giving E an __init__, makes it work — so the idiomatic empty exception class is the broken one"
status: done
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

## Resolved 2026-08-02 — commit a0cf42cb6

**Narrower than filed, and the ticket's "where to look" was right.** Measured:
CONSTRUCTION alone crashes — `e = E()` with no `raise` anywhere. The `raise`
in the repro was incidental.

NilPy's `Exception` resolves to the **RTL's** Exception, whose `Create(msg)`
takes a REQUIRED message. `PyClassCreate`'s default-fill loop only supplies
parameters that carry a declared default, so it stopped, and the call went out
one argument short: the callee read whatever happened to be in the register as
its message string. That is why `raise E("m")` and an own `__init__` both
worked — each supplies the argument — and why the failure alternated between a
segfault and silence.

`Exception()` with no arguments is valid Python and `str(Exception())` is the
empty string, so the fix supplies an empty message rather than a diagnostic.
Restricted to STRING parameters: those are the ones with a meaningful empty
value, and the restriction keeps this from quietly papering over an under-called
constructor of any other shape, which should stay visible.

### A bug of my own, found by this ticket's test

Writing the gate list surfaced that [[bug-nilpy-one-line-def-and-class-bodies-do-not-parse]]'s
class half, which I had landed an hour earlier in 9e5d2a80a, was **not** as
contained as I claimed. I argued an empty class body reaches no INDENT-keyed
pre-pass. Wrong: `PyRegisterClassFieldsPrepass` locates a class body by scanning
to the first `tkIndent`, and a one-line body has none — so the scan ran on to the
NEXT class's indent and registered that class's members against the one-line
class. `class G(Exception): pass` followed by a class with an `__init__` failed
with "unresolved forward: G.create".

Fixed in the same commit: the scan stops at the header's COLON and reads the
shape from what follows (`COLON NEWLINE INDENT` = indented, anything else =
one-line), and a one-line body registers an **empty member span** rather than
being skipped — the pass also computes the class SIZE and emits its VMT, so
skipping it left the class unsized and every construction crashed. Same
correction in `PyParseClass`'s own one-line branch.

Recorded because the reasoning error is the interesting part: "an empty body has
no members, so the member scanners cannot be affected" ignored that a SCANNER can
be wrong about where the body *ends*, not just what is in it.

### Verified

`test/test_nilpy_empty_exception_subclass.npy` (+ `.expected`, wired into
`make test-nilpy`), byte-identical to CPython: bare `raise E()` caught by its
own name and by `except Exception`; with a message; two sibling empty subclasses
told apart by their `except` clauses; a subclass with `__init__`; and the
one-line `class G(Exception): pass` spelling, which is the case that exercises
the span scanner.

Uncaught `raise E()` now reports `Unhandled exception: E` instead of exiting 0
in silence.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical.

## Log
- 2026-08-02 — resolved, commit a0cf42cb6.
