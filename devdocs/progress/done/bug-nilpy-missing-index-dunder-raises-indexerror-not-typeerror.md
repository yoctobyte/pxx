---
track: N
prio: 35
type: bug
summary: "Indexing a sequence with an object that has no __index__ raises IndexError (the handle used as a position) where CPython raises TypeError — loud but misleading, and a small handle would index the wrong element instead"
status: done
owner: claude-AN
---

# A missing `__index__` at a subscript raises IndexError, not TypeError

- **Type:** bug (NilPy semantics, misleading diagnostic) — **Track N**
- **Found:** 2026-08-03, closing
  [[bug-nilpy-unary-numeric-dunders-return-raw-handle]]. Everything that ticket
  covered is fixed; this is the not-declared half of `__index__`.

## Measured

```python
class N: pass
xs = [10, 20, 30]
xs[N()]        # CPython: TypeError    pxx: IndexError: list index out of range
```

The instance HANDLE is used as the position. It raises only because the handle
is far past the end — a small enough handle would silently index the wrong
element, which is the shape this whole family keeps producing.

## Why it was not fixed with the rest

Raising needs to know the receiver is a SEQUENCE, and the site that would raise
does not know. `PyIndexCoerce` sees only the index expression, and it is called
from a dict subscript too, where an object IS a legal key. Getting this wrong in
the obvious place collapsed object dict keys onto their `__index__` value —
measured, and recorded on the parent ticket.

`PyClassWantsIntIndex` (added there) is the predicate to reuse: it already
answers "does this receiver want an integer". The work is threading the raise
through the sites that have the receiver, and choosing a pylib raiser
(`PyUnsupportedOperandError` is the nearest existing one; Python's own message
is "list indices must be integers or slices, not N").

## Gate

A `.npy` diffed against CPython: list, str and bytes subscripted by an object
with no `__index__`, each inside a `try/except TypeError` that must run its
handler; a dict subscripted by the same object, which must still WORK; and the
declared-`__index__` cases still green.


## Resolved 2026-08-04 — three subscript paths, not one

`PyIndexTypeError` (pylib) raises CPython's own message — "list indices must be
integers or slices, not N" — and is a **function returning Int64** on purpose:
that lets it stand in for the INDEX EXPRESSION at every site, so the getter is
never reached and each path needed only a two-line substitution rather than a
rewrite.

The ticket's analysis was right about where the knowledge lives: the raise needs
to know the receiver is a SEQUENCE, and `PyIndexCoerce` sees only the index and
is called from a dict subscript too, where an object IS a legal key. So the
decision moved to the callers, which have the receiver, and `PyIndexSeqKind` /
`PyIndexSeqKindCi` answer "which sequence, if any" — deliberately empty for a
dict and for a VARIANT receiver, which may hold a dict at run time.

### What the measurement added: there are THREE such callers

Fixing the obvious one left two thirds of the bug in place, and each showed up
only when the previous was fixed:

| path | receiver shape |
| --- | --- |
| `PyMakeSuffixIndex` | a LITERAL receiver |
| `parser.inc`'s default-property path (gated by `PyClassWantsIntIndex`) | a NAMED list/bytearray |
| `PyMakeStrIndex` | a NAMED str |

The str path needs no receiver test at all — a str is always a sequence — while
the other two must ask, which is why the helper is split into "which kind" and
"raise for this kind".

### Verified

`test/test_nilpy_index_dunder_typeerror.npy`, wired into `make test-nilpy`:
list, str and bytearray subscripted by an object with no `__index__`, each
inside a `try/except TypeError` that must RUN its handler; a dict subscripted by
the same object, which must still work; and the declared-`__index__` cases still
returning the coerced element. All named receivers, so the paths that were
missed cannot hide again. Diffed against CPython, identical.

`tools/gate.sh quick` GREEN, self-host byte-identical — after the FPC seed
canary caught duplicate forwards (declared in both `parser.inc` and
`pyparser.inc`; the former is included first and already covers the latter).

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit PENDING-COMMIT.
