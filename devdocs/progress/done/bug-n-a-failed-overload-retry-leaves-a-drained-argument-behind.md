---
slug: bug-n-a-failed-overload-retry-leaves-a-drained-argument-behind
title: a failed overload retry left the drained argument behind, so a call that omitted a trailing default passed list(x) where the source said x
summary: >
  PyFixIterableArgs has a SPECULATIVE arm: when no overload matched, it drains
  every user-iterable argument -- pyiter_drain(pyiter_of_userobj(x)) -- and the
  caller retries the match once. That is what gives `sum(bag)` the
  `sum(TPyList)` row. The drain rewrites the caller's argument list IN PLACE,
  and when the retry also came back -1 the rewrite stayed. Every path below the
  match reads that list, including the one that fills a callee's missing
  trailing DEFAULT -- so the call compiled, ran, and handed the callee
  list(bag). The callee then dispatched a method through TPyList's table.
  Fixed by recording what the speculative arm replaced and restoring it when
  the retry fails. Fixture
  test_nilpy_a_failed_overload_retry_restores_the_drained_argument.
track: N
type: bug
prio: 90
owner: frank-user
status: done
---

## The three conditions, each measured on its own

1. The argument's class declares `__iter__`. Not "a dunder": `__len__`,
   `__repr__`, `__eq__` and two extra plain methods are all clean.
2. The call omits a trailing defaulted argument. The same call with the
   default supplied is correct.
3. The callee is defined in a NON-MAIN module. A def in the main module
   resolves by another path and never reaches the retry.

Conditions 1 and 2 were measured here; all three were confirmed
one-variable-at-a-time by the lekkerzeilen-c8 seat, which also supplied the
first four-line reproducer and established that `ui.py`, the `for` loop, the
imported tuple, the local name shadowing the method, and which method is called
are all irrelevant.

## What said it, and it was the compiler's own decision point

Instrumented at the branch rather than inferred from the crash:

```
FIXITER procIdx=-1   i=0 nArgs=1 pRec=0 listCi=34 base+list=50
FIXITER retry name=x2 -> procIdx=-1
FIXITER procIdx=2097 i=0 nArgs=2 pRec=0 listCi=34 base+list=50
```

The one-argument call fails to match, is drained, **fails to match again**, and
the drain is never taken back. The two-argument call matches at once and
nothing is touched.

The fault is `mov (%rdi),%rax ; call *0x28(%rax)` -- a virtual dispatch through
the object's class pointer, where the object is a TPyList and slot 0x28 of its
table holds data, not code.

## Why the crash looked like a threading or a default-value bug

The argument arrives at the call site perfectly formed -- the caller's variant
slot holds `{VType=7, <the drained list>}` -- and the DEFAULT itself binds
correctly, so a probe that prints `title` reports `T` and clears the obvious
suspect. The damage is only visible at the first USE of the earlier argument,
in the callee, in a class the source never mentions.

## The other direction, which the fixture also pins

The speculative drain must still happen where it is meant to. `sum(h)` and
`sorted(h)` over the same object are rows in the fixture, because "never drain"
would otherwise pass it.
