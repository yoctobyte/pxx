---
slug: feature-n-nilpy-has-no-__del__-and-its-absence-is-load-bearing-in-an-open-fork
title: "NilPy implements no `__del__`, in an otherwise near-complete dunder protocol — and the heap-lock fork is currently reasoning FROM its absence"
track: N
type: feature
prio: 35
status: backlog
owner: ""
created: 2026-09-06
found-by: owner (asked directly), measured by frankuser
blocked-by: [decide-a-how-should-the-nilpy-managed-finalize-re-enter-the-heap-lock]
summary: "`grep -rn __del__ compiler/ lib/ test/` is EMPTY at da2fea0fd — no lexer token, no parser arm, no runtime call, no test, and no entry in nilpy-semantics-divergences.md, so it is an unrecorded gap rather than a chosen divergence. That is a hole in an otherwise near-complete protocol family: __init__, __enter__/__exit__, __iter__/__next__, __getattr__, __getitem__/__setitem__/__delitem__, __call__, __bool__, __len__, __contains__, __repr__/__str__, __index__, every arithmetic operator with its reflected and in-place forms, and the six comparisons are all present. THE REASON IT IS NOT MERELY MISSING: decide-a-how-should-the-nilpy-managed-finalize-re-enter-the-heap-lock argues option (b) -- defer the nested release -- on the ground that its observable finalizer-ORDERING change is 'a cost against a feature nobody has built'. That is true today and it stops being true the moment this lands, so implementing __del__ under (b) reintroduces exactly the cost (b) was costed as not having. Under (a), a reentrant lock, a user finalizer can allocate and the ordering question does not arise. So this is not independent work: it should be built on whichever arm the owner picks, and it is an argument for (a). Siblings, also absent and also unrecorded, filed here as a note rather than as tickets: __new__, __slots__, __format__."
---

# NilPy has no `__del__`, and the fork is reasoning from that

Asked by the owner, 2026-09-06: *"what is with the missing `__del__` dunder? that
is standard python?"* It is, and we do not have it.

## The measurement

At `da2fea0fd`: `grep -rn '__del__' compiler/ lib/ test/` returns **nothing**.
Not a lexer token, not a parser arm, not a runtime hook, not a test. It is also
**not in `devdocs/dev/nilpy-semantics-divergences.md`**, so it has never been
written down as a decision — it is a gap, not a divergence.

**It is a hole in a family that is otherwise nearly complete.** Present today:
`__init__`, `__enter__`/`__exit__`, `__iter__`/`__next__`, `__getattr__`,
`__getitem__`/`__setitem__`/`__delitem__`, `__call__`, `__bool__`, `__len__`,
`__contains__`, `__repr__`/`__str__`, `__index__`, `__abs__`, `__invert__`,
`__class__`, `__cause__`, all six comparisons, and every arithmetic operator
with its reflected (`__radd__`…) and in-place (`__iadd__`…) forms.

**NilPy is UPWARD compatible with CPython, one direction.** Accepting what
CPython rejects is a feature; *lacking* what CPython has is a plain gap.

## Why it is not independent work

`decide-a-how-should-the-nilpy-managed-finalize-re-enter-the-heap-lock` costs its
option (b) — defer the nested release to a per-thread pending list drained after
the lock drops — and dismisses the ordering objection like this:

> *"NilPy has no `__del__` at all … So there is no user-visible finalizer today
> whose ordering (b) could change, and its cost is a cost against a feature
> nobody has built."*

**Correct today, and it is exactly this ticket that makes it false.** Building
`__del__` on top of (b) reintroduces the cost (b) was priced as not having, and
does so in the one area where NilPy's upward-compatibility promise bites: CPython
defines refcount-driven finalization order, and (b) moves a nested finalizer to
after the outer walk.

Under (a), the reentrant lock, the question does not arise — a user finalizer
runs in place and may itself allocate.

**So: do not build this before the fork is ruled, and treat it as an argument
for (a) while the fork is open.** That is why it carries a hard `blocked-by`
rather than a remark.

## What is NOT in scope here

`__new__`, `__slots__` and `__format__` are also absent and also unrecorded.
They have no coupling to the lock fork and no named program asking for them, so
they are noted here rather than filed — **a corpus census is not demand**, and a
ticket per missing dunder is how a backlog stops meaning anything.

## What would make this worth more than 35

A named program we want to compile that uses `__del__`. Absent that, it is a
protocol hole worth closing for completeness and worth exactly what completeness
is worth — which is why it is not ranked higher despite being standard Python.
