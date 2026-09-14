---
slug: bug-n-a-set-comprehension-over-releases-its-own-list
title: a set comprehension handed its list back borrowed while the caller released it as owned
summary: >
  `PyParseSetComp` yielded `pylist_mark_set(temp)` as the comprehension's VALUE.
  That marker is an IDENTITY function, so it returns a BORROWED alias of the
  hidden temp, while the caller of a class-returning call owns its result and
  releases it -- one release against no retain, and the temp's own scope-exit
  release on top. The refcount went NEGATIVE and the list was freed while still
  referenced; the next allocation reused the block. `frozenset(iterable)` had
  the same shape, `pylist_mark_frozenset` wrapped around a `pyset_of` call.
  Fixed by hoisting the set stamp as a STATEMENT and yielding the bare temp --
  the shape the `{a, b}` literal already used -- and by giving frozenset its own
  `pyfrozenset_of` so nothing wraps an owned call result. The visible half is
  `return {x for x in xs}`, which answered len 0 and now answers 3.
  Fixture test_nilpy_a_set_comprehension_does_not_over_release_its_own_list.
track: N
type: bug
prio: 80
owner: frank-user
status: done
---

## Minimal

    def f(xs):
        return {x for x in xs}
    print(len(f([1, 2, 3])))

    pxx     0
    CPython 3

The set escapes the function, is freed on the way out, and the caller reads an
empty container. The BOUND spelling (`s = {x for x in xs}; return len(s)`)
answers correctly and still over-releases -- it just happens not to lose the
block before the read, which is why this went unnoticed.

## The measurement

`-dPXX_OBJTRACE` with a non-fatal trap on `rc < 0`, over a matrix chosen so the
clean rows and the broken rows differ only in the construct. Both numbers every
time, because the FIRST candidate fix zeroed the underflows and leaked:

    row              baseline                 fixed
    v_set            underflow=1  live=1      underflow=0  live=1
    x_len            underflow=1  live=1      underflow=0  live=1
    x_bind           underflow=1  live=1      underflow=0  live=1
    x_ret            underflow=0  live=1  (out 0!)  underflow=0  live=2 (out 3)
    y_frozen         underflow=1  live=2      underflow=0  live=2
    y_setcomp_arg    underflow=1  live=1      underflow=0  live=1
    y_setlit         underflow=0  live=0      underflow=0  live=0
    x_lit            underflow=0  live=0      underflow=0  live=0
    x_dictcomp       underflow=0  live=1      underflow=0  live=1
    x_setcall        underflow=0  live=2      underflow=0  live=2
    v_setlist        underflow=1  live=1      underflow=0  live=1
    y_emptyset       underflow=0  live=0      underflow=0  live=0
    y_emptyfrozen    underflow=0  live=0      underflow=0  live=0
    m_modlevel       underflow=0  live=2      underflow=0  live=2
    u_base           underflow=0  live=1      underflow=0  live=1

`x_ret`'s extra live object is the RETURNED set now surviving; its `out` column
moved from the wrong answer to the right one in the same step.

## The fix that was measured and NOT taken

Adding `PXXObjRetain` inside `pylist_mark_set` / `pylist_mark_frozenset` --
"the identity function returns OWNED". It zeroes every underflow at no cost to
the broken rows AND leaks one object on `y_setlit` and `x_lit`, the set-LITERAL
path, which was already clean. The reason is structural and is why a shared
helper cannot serve here: the marker is applied at four sites with two
different ownership conventions.

    pyparser.inc:22119  set LITERAL       hoisted STATEMENT, result discarded
    pyparser.inc:7745   empty `set()`     wraps a GetMem node -- balanced
    pyparser.inc:7723   `frozenset(it)`   wraps a pyset_of CALL -- over-released
    pyparser.inc:27033  set COMPREHENSION wraps a borrowed ident -- over-released

Adding a retain fixes the last two and leaks at the first. So each broken site
was moved onto the convention its clean neighbour already uses, and the marker
stayed an identity.

## Why the literal was the control worth having

The literal and the comprehension build the SAME container by the SAME loop and
differ only in how the stamp is spelled. That is what made "the stamp, not the
build" a measurement rather than a guess -- and it is what caught the first
candidate, since the literal is the row a blanket retain breaks.

## Guard

`test_nilpy_a_set_comprehension_does_not_over_release_its_own_list`. It leads
with the RETURNED case, which is the row a value assertion can actually fail
(0 against 3 on the unfixed compiler); the rest -- allocations between the
build and the read, a nested comprehension, the set operators, the tags -- is
there so a repair cannot buy the refcount back by breaking the kind. No lambda
anywhere in it: a peer measured that a lambda returning a user-class instance
yields None, so a lambda-wrapped harness is not trustworthy on this compiler
(`bug-n-a-lambda-returning-a-user-class-instance-yields-none`).

## What it did NOT fix

lekkerzeilen's world path still exits 139 at the same position, after
`chart 512x512 ... in 3.4 s`. Measured on the whole demo with
`-dPXX_OBJTRACE`: **3151 underflow events across 2184 addresses**, against
3186 / 2218 before. So this site is real and accounts for roughly 35 of them.
The over-release class is the right one -- the per-object shape is still
`A 1 / R 2 / r 1 / r 0 / F / r -1`, a stale reference released after the free --
and the dominant producer is something else.

## An instrument note, because it cost a wrong number first

A NEGATIVE refcount does not print with a leading minus. This RTL writes it
with a TRAILING minus (`1-`) or as an unsigned wrap (`4294967294`), so
`grep ' -[0-9]'` matches nothing and reports a clean run. It reported the demo
at **zero** underflows for several minutes. The pattern that works is
`grep -a '[0-9]-$\|42949672'`. The earlier matrix escaped this only because a
temporary `WriteLn` probe in `PXXObjRelease` printed the count as an ordinary
Int64 -- i.e. the detector was reading the PROBE, not the trace, and stopped
working the moment the probe came out.

## Log
- 2026-09-14 — resolved, commit c53d9ab55.
