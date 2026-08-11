---
track: N
prio: 50
type: bug
blocked-by: []
status: done
owner: claude-A
---

# A lambda with FOUR or more parameters segfaults when called

- **Type:** bug (SEGFAULT on valid Python) — **Track N**
- **Found:** 2026-08-11, lifting multi-parameter lambdas
  ([[bug-nilpy-multi-parameter-lambdas-are-still-interpreted]]).
- **Pre-existing on `pinned`** — controlled, identical crash there.

```python
q = lambda a, b, c, e: a + b + c + e
print(q(1, 2, 3, 4))
```

CPython prints `10`. pxx **segfaults** (exit 139). It compiles clean, so there
is no diagnostic.

## Where it is

Lambdas with 1..3 parameters are LIFTED to real procs as of 2026-08-11; four or
more keep the interpreted pyeval source-closure fallback, and **that fallback is
what crashes**. The lift threshold is 3 because the bound-fn bridge
`pyboundfn_callvn` carries `a0, a1, a2` — three own arguments — and places
`NOwn` of them before the bound slots.

So there are two ways to fix it and they are worth weighing against each other:

1. **Fix the interpreted path** — the right fix regardless, because a crash on
   valid Python is the worst outcome available and the fallback is reached by
   other shapes too (a lambda capturing a managed string, a body the lifter
   refuses).
2. **Widen the bridge** to 4+ own arguments, so ordinary lambdas of that arity
   are compiled and never reach the fallback. The `TBF*` table already goes to
   32 slots; it is the `a0/a1/a2` parameter list of `callvn` and its
   `pyvar_callv2/3` callers that stop at three.

(1) is the bug; (2) is the performance follow-on and would shrink the fallback's
exposure. Do (1) first — do not let (2) hide it.

## Gate

The program above printing `10`; a 5- and 6-parameter lambda too; a 4-parameter
lambda that also CAPTURES an enclosing local; `make test-nilpy` green.

## Resolution (2026-08-11) — the ticket's own premise was wrong, measured

I filed this as "the interpreted fallback crashes, fix that first". Measuring
says otherwise: the fallback is fine and **the DISPATCH was missing**.

`pyvar_callv0..3` exist; arity 4 had none, so the call kept the older lowering,
which unboxes the callee and calls through its payload as a CODE ADDRESS. That
is correct for a plain def and a segfault for a lambda, whose value is a closure
OBJECT. The control that shows it: `f = add4; f(1, 2, 3, 4)` — a def bound to a
name, same arity, same call shape — has always worked. The two differ only in
what the name holds, which is why this read as a lambda-arity bug.

So neither of the two fixes the ticket weighed was the one needed: the crash is
on the CALL side, and lifting 4-parameter lambdas (option 2) would have hidden
it for lambdas while leaving every other closure-valued name at that arity
crashing.

Added `pyvar_callv4` (mirroring callv3: interpreted closure via a TPyList, class
reference constructs, plain code address called directly) and the
`pybound_callv4` bridge it needs — `f = some_def` binds a callback PAIR even for
a plain def, so every dynamic call at this arity comes through that bridge and
there was no arity-4 member of it.

**A first cut raised a TypeError for the callback shape instead**, which
regressed the def-through-a-name row that already worked. It was caught at once
because the test covers all five callable shapes at arity 4 rather than the one
the ticket reported — the reported shape alone would have passed.

Verified against CPython: an interpreted 4-parameter lambda, the same with a
CAPTURE, a def through a name, a class reached as a value, and the arity-3
`__call__` neighbour. `make test-nilpy` EXIT=0, `gate.sh quick` GREEN. The
isolated repro segfaults on `pinned` (rc=139) and prints 10 at HEAD.

Still true, and now recorded where it belongs rather than as this bug: a lambda
of 4+ own parameters is not LIFTED, because the bound-fn bridge carries three
own arguments. That is a performance limit, not a crash, and it is
[[bug-nilpy-multi-parameter-lambdas-are-still-interpreted]]'s remainder.

## Log
- 2026-08-11 — resolved, commit cbb1ebbb4.
