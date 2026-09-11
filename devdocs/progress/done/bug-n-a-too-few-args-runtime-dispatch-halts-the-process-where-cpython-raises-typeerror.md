---
slug: bug-n-a-too-few-args-runtime-dispatch-halts-the-process-where-cpython-raises-typeerror
title: A run-time dispatched call with too few arguments HALTS the process, where CPython raises a catchable TypeError
track: N
type: bug
prio: 45
status: done
---

## Summary

**RESOLVED 2026-09-11** — now a catchable `TypeError`, byte-identical to
CPython on the try/except row. Inert for `$(PXX_STABLE)` consumers until a pin.

`pyeval`'s `PyHostCall` reports too-few-arguments with `writeln` + `Halt(1)`.
CPython raises `TypeError`, which a program can catch. So a NilPy program that
wraps a dynamically dispatched call in `try/except TypeError` cannot catch it —
the process exits instead, with a message on stdout that is not a Python
traceback and carries no line number.

## Measured 2026-09-11, compiler `f9fb672ee109`

| program | pxx | CPython |
| --- | --- | --- |
| `def f(d): d.get()` on a dict | `pyeval: too few args to get (need 1, got 0)`, rc=1 | `TypeError: get expected at least 1 argument, got 0` |
| `def f(xs): xs.index()` on a list | `too few args to index (need 1, got 0)`, rc=1 | `TypeError: index expected at least 1 argument, got 0` |
| `det.analyze(1)` vs `analyze(self, chords, fn, sections=None)` | `too few args to analyze (need 3, got 1)`, rc=1 | `TypeError: Det.analyze() missing 1 required positional argument: 'fn'` |

The DIAGNOSIS agrees in all three rows. Only the delivery differs: an
uncatchable exit versus an exception.

## Why it is filed now, and why the prio is not lower than it looks

It was already reachable — every call the open-world NAME fall-through defers
lands here. It became **more** reachable on 2026-09-11: the arity fall-through
(`bug-n-a-method-call-is-refused-on-arity-from-the-candidates-compiled-so-far-so-import-order-decides`)
deliberately routes a class of calls to this path that used to be refused at
compile time. That trade is the right one — a refusal that import order decides
is worse than a loud run-time error — but it moves programs onto a path whose
failure mode is an exit, so the exit is now this frontend's problem rather than
an edge of it.

## Fix direction

`raise TypeError.Create(...)` in place of the `writeln`/`Halt(1)` pair in
`PyHostCall`, wording it the way CPython does. `TypeError` is already raised a
few lines below in `PyDynMethN` for the callable-field keyword refusal, so the
class and the unit are both already there.

**The one thing to check before changing it**: `PyHostCall` is reached from the
Pascal side as well as from NilPy, and a `raise` crossing a boundary that today
gets a `Halt` is a different control flow for those callers. Establish who else
calls it before swapping the mechanism — the message is the cheap half.

## Not the same as too MANY arguments

Surplus arguments are dropped rather than reported — `nargs` above `n` is not
checked at all, and CPython raises there too. Measured only in passing while
looking at the too-few path, so it is recorded as unverified: establish it
before fixing it.

## RESOLVED 2026-09-11, same day it was filed

`compiler/builtin/pyeval.pas`, `PyHostCall`: the `writeln` + `Halt(1)` pair
becomes `raise TypeError.Create(...)`.

**The prerequisite this ticket set for itself was one grep and it passed.**
Every caller of `PyHostCall` is in that unit — five of them — so no Pascal-side
caller outside it sees the control-flow change, and a `Halt` is unrecoverable,
so nothing could have been relying on it to return. Filing it with an unchecked
prerequisite was the same shape as the arity ticket's cost estimate; checking it
took a minute.

| | before | after | CPython |
| --- | --- | --- | --- |
| `det.analyze(1)` | `pyeval: too few args to analyze (need 3, got 1)`, process exits | `TypeError: analyze() missing positional argument(s): its parameter list holds 3 and only 1 could be bound` | `TypeError: Det.analyze() missing 1 required positional argument: 'fn'` |
| the same wrapped in `try/except TypeError` | uncatchable, program dies | `caught: TypeError` then `still running` | `caught: TypeError` then `still running` |

The catch row is byte-identical to CPython.

### The count is deliberately NOT called "required", and the first draft got it wrong

The first wording said `missing 2 required positional argument(s)` where CPython
says `missing 1`. All this path knows is `mi^.Arity`, which counts DEFAULTED
parameters too. The gap itself is real — defaults are already bound by the time
the check runs, measured: `d.zqx(1)` against `zqx(self, a, b=5)` answers **6**
under both pxx and CPython, and `det.analyze(1, 2)` against
`analyze(self, chords, fn, sections=None)` answers **7** under both. So the
message now states only what the runtime can see. **A diagnostic that
over-counts is the same defect as one that under-reports**, and it would have
shipped inside a commit whose headline was "make the message truthful".

### Inert until a pin

This is `compiler/builtin/**`. Programs built with `$(PXX_STABLE)` keep the
`Halt` until the next pin carries it. `make compiler/pascal26` prints
`converged` at `465845b20d1e`, the same sha as before the wording edit — the
compiler binary is unaffected by it, which the stamp said first and a cleared
stamp confirmed.

### Not fixed here, and it was measured only in passing

Surplus arguments are still dropped rather than reported; `nargs` above `n` is
not checked. CPython raises there too. Recorded as unverified in the body above
and still unverified — establish it before fixing it.

## Log
- 2026-09-11 — resolved, commit a00d94926.
