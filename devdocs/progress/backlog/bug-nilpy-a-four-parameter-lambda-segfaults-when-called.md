---
track: N
prio: 50
type: bug
blocked-by: []
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
