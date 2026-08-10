---
track: N
prio: 60
type: bug
summary: "A LIFTED lambda called with the wrong argument count does not raise: extra arguments are silently dropped (returns a wrong answer) and a missing one SEGFAULTS. The pyeval closure path enforces arity via pyclosure_setarity; the bound-fn path has the fields (NOwn/NDef) but no check."
---

# A lifted lambda does not enforce arity — wrong answer, or a segfault

- **Type:** bug (silent wrong answer + crash) — **Track N**
- **Found:** 2026-08-10, by `test/test_nilpy_lambda_arity.npy` catching a
  widening of the lift gate that was reverted the same day.
- **Pre-existing**, and that is the point: it does NOT need the reverted change
  to reproduce.

## Measured on `pinned`

`lambda x: abs(x)` contains a call, so it is lifted **today**, with no change:

```python
f = lambda x: abs(x)
print(f(1, 2))     # CPython: TypeError
                   # pinned:  1   <- extra argument silently dropped
```

The closure path, which handles call-free bodies today, gets it right:

```python
g = lambda x: x
g(1, 2)            # pinned: TypeError  (correct)
g()                # pinned: TypeError  (correct)
```

Same language construct, two answers, decided by whether the body happens to
contain a call. When the lifted path is the one taken, a missing argument is
worse than a wrong answer:

```
g()   under a lifted g  ->  SEGFAULT
```

## Why the two paths differ

The pyeval closure records its legal arity — `pyclosure_setarity(obj, req, tot)`
— and checks it. The bound-fn path already carries the same information:
`TBoundFnObj.NOwn` (own parameters) and `NDef` (how many trailing ones are
defaulted), set by `pyboundfn_setown` / `pyboundfn_setdefaults`. The legal range
is `NOwn - NDef .. NOwn`. **Nothing consults it at call time.**

So this is a missing check, not missing information.

## Blocks

[[bug-nilpy-every-lambda-is-interpreted-instead-of-compiled]]. Widening the lift
so ordinary lambdas compile is worth ~6.9x per call, but it moves lambdas from
the path that checks arity onto the path that does not — turning correct
TypeErrors into wrong answers and crashes. Land this first, then widen.

## Fix direction

Enforce the range in the bound-fn call path (`pyboundfn_callv` / `callvn` /
`pyboundfn_call_ptr`) using `NOwn`/`NDef`, raising `TypeError` with the same
shape the closure path produces so `test_nilpy_lambda_arity.npy` passes on
either route. Note the defaulted range is inclusive at BOTH ends — that test's
header is explicit that a check which can only turn working code into raising
code has to be exactly right about what is legal.

This is `compiler/builtin/**` (pylib/pyeval), so it needs `make stabilize-fast`
+ `make pin`, not just the quick gate.

## Gate

`test/test_nilpy_lambda_arity.npy` green with the lift gate BOTH as it is now
and widened to `Result := (depth = 0)` — the second is the real check, since it
is the configuration that exposed this.
