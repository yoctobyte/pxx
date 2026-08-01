---
summary: "NilPy: `\"{1}{0}\".format(a, b)` ignores the explicit indices and substitutes left-to-right — silently prints the arguments in the WRONG ORDER"
type: bug
track: N
prio: 60
---

# `str.format` ignores explicit positional indices

- **Type:** bug (NilPy semantics, silent wrong value) — **Track N**
- **Opened:** 2026-08-01, from a differential sweep of the string method surface
  against CPython (self-hosted binary at `c7d64813b`).

## Measured

```python
print("{1}{0}".format("a", "b"))   # CPython: ba    pxx: ab   WRONG
print("{0}{1}".format("a", "b"))   # CPython: ab    pxx: ab   ok
print("{}{}".format("a", "b"))     # CPython: ab    pxx: ab   ok
```

Only the REORDERING case is wrong: `{}` and `{0}{1}` happen to agree with
left-to-right substitution, so the bug is invisible until an index actually
reorders. The number inside the braces is being ignored entirely rather than
used as an argument index.

## Why it matters

Silent and order-dependent. `"{1} {0}".format(first, last)` is a common way to
swap name order, and `"{0} {0}"` (repeating one argument) is the other standard
use — both produce plausible-looking output that is simply wrong, with no error.
It will most often surface as a user-visible string with two fields transposed,
which is easy to mistake for a data problem rather than a compiler bug.

## Scope to check when fixing

- `{0}` repeated: `"{0}-{0}".format("x")` → `x-x`, and it must NOT consume two
  arguments.
- Mixing automatic and explicit numbering is a **ValueError** in CPython
  (`"{}{0}".format(...)`), not a silent answer.
- Index out of range → `IndexError`.
- Named fields (`"{name}".format(name=…)`) and format specs (`"{0:>5}"`,
  `"{:.2f}"`) — check whether those parse at all today before assuming only the
  index is missing.
- `%`-formatting is a separate implementation and tested elsewhere; this ticket
  is `str.format` only.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython covering each bullet above — in particular a case whose expected output
DIFFERS from left-to-right substitution, since that is the only shape that can
distinguish the broken implementation from the correct one.
