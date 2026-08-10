---
track: N
prio: 60
type: bug
summary: "A LIFTED lambda called with the wrong argument count does not raise: extra arguments are silently dropped (returns a wrong answer) and a missing one SEGFAULTS. The pyeval closure path enforces arity via pyclosure_setarity; the bound-fn path has the fields (NOwn/NDef) but no check."
status: done
owner: claude-N
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

## Resolved 2026-08-10 — and the lambda widening relands on top of it

**Fix.** `PyBoundFnArityBad`, the bound-fn twin of the existing
`PyClosureArityBad`, checked at the four callable-value entry points
(`pyvar_callv0..3`) beside the closure check. `PyRaiseArity` was already generic
(it takes only n/lo/hi), so the message and the `TypeError` class are shared —
a lambda now reports the same thing whichever route it took.

**No new fields, deliberately.** `TBoundFnObj`'s own comment records that
growing the record pushed it into the next allocator size class and MEASURABLY
made the still-leaking shapes leak more. The legal range is instead read from
the fields already there: `NDefBase .. NDefBase + NDef`, where `NDefBase` is the
caller-side index at which defaulted params begin — which is exactly the count
of REQUIRED arguments. `pyboundfn_new` now defaults it to **-1 = unchecked**, so
every bound-fn the lambda lifter did not build (nested defs, the callback
bridges) keeps the lenient behaviour those paths depend on.

`NOwn` cannot serve this purpose and that is worth recording: a zero-parameter
lambda is lifted under a DUMMY own parameter, so `lambda: 42` and `lambda x: x`
both have `NOwn = 1`.

The parser side is one guard: `pyboundfn_setdefaults` is now emitted even when
`dcCount = 0`, because that call is also how a lifted lambda declares its arity.

**The pre-existing hole is closed.** On pinned, `lambda x: abs(x)` — already
lifted, because its body contains a call — silently dropped an extra argument
and returned `1`. It now raises `TypeError`, matching CPython.

### Relanded with it

[[bug-nilpy-every-lambda-is-interpreted-instead-of-compiled]]'s widening, which
had to be reverted (88eb07f9d) for exactly the gap this ticket closes. Verified
in the configuration that exposed the problem, per this ticket's own gate:
`test_nilpy_lambda_arity.npy` green with the lift gate BOTH as it was and
widened.

    f = lambda x: x
    f(1, 2)   was: returns 1     now: TypeError   (CPython: TypeError)
    f()       was: SEGFAULT      now: TypeError   (CPython: TypeError)

and the perf win is retained: 1.46 s -> 0.41 s over 200k calls, with no body
source left embedded in the binary.

### A second, pre-existing bug fell out

[[bug-nilpy-lifted-lambda-cannot-capture-a-managed-string]] — the lift silently
skipped managed-string captures, so the lifted body referenced a name not in its
scope. Fixed here because the widening would otherwise have turned working
closure code into a compile error. Caught by the test-family sweep, not by
`gate.sh quick`.

Gate: self-host fixedpoint, `gate.sh quick` GREEN, a 79-test family sweep
(0 bad), and `make stabilize-fast` + `make pin` (v253) because this touches
`compiler/builtin/**`.

## Log
- 2026-08-10 — resolved, commit f7bb7a9d3.
