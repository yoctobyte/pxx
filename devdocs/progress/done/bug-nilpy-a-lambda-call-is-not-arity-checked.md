---
track: N
prio: 60
type: bug
summary: "NilPy: a call through a lambda ignores arity — extra arguments are silently DROPPED and missing ones silently become None, so `f = lambda x, y=k: x*y; f(3, 4)` returns 6 instead of 12 with no diagnostic"
status: done
owner: claude-A-N
---

# A lambda call is not arity-checked — wrong values, no diagnostic

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-07, bughunting with `tools/pydiff.py`.

## Measured (self-hosted fixedpoint at `8f1852f27`)

A call through a lambda accepts **any** argument count. Extra arguments are
discarded; missing ones arrive as `None`. CPython raises `TypeError` for both.

```python
f = lambda x: x
print(f(1, 2))     # CPython: TypeError    pxx: 1
print(f())         # CPython: TypeError    pxx: None
```

The damaging instance is a lambda with a **defaulted parameter**, because there
the program is perfectly ordinary CPython and simply gets a wrong number:

```python
k = 2
f = lambda x, y=k: x * y
print(f(3))        # CPython 6    pxx 6     <- agrees
print(f(3, 4))     # CPython 12   pxx 6     <- WRONG, silently
```

`f(3, 4, 5)` likewise returns the `y=k` answer rather than raising.

**A `def` is not affected** — it is arity-checked at compile time, correctly:

```python
def g(x): return x
print(g(1, 2))     # pascal26: error, candidates: g(Variant)  -- correct
```

## Why it matters more than the arity check itself

This is the escape-hatch form that
[[bug-nilpy-closure-over-a-loop-variable-captures-by-value]] relies on. That
ticket's 2026-08-07 recon measured `lambda x=j: x` and recorded **"the escape
hatch WORKS"**. It works only as long as the caller never supplies the argument;
the moment it does, the default silently wins. Worth reading alongside that
ticket before its fix session.

It also contradicts a claim in
[[feature-nilpy-small-syntax-gaps-found-by-the-2026-08-06-sweep]], which lists
`lambda x, y=1: x + y` as a clean loud failure and states that **none** of that
sweep's rows is a silent wrong value. The loud failure fires only for a
*non-name* default; with a plain-name default (the documented supported form)
the same shape compiles and returns the wrong value.

## Root cause — hypothesis, NOT yet measured

`PyParseLambdaStub` (`compiler/pyparser.inc`, ~5599) treats every `name=value`
in a lambda header as a **build-time capture**, not as a parameter: the name is
never added to `pNames`, so it does not count toward the lambda's arity, and its
value is bound once at lambda creation via `pyboundfn_bind*`. The lift is gated
on `nParams <= 1` and the bound-fn bridge passes exactly one argument
(`a0var=1`), so any further caller argument has nowhere to land.

If that is right, making a defaulted parameter caller-overridable needs a bridge
that passes more than one argument — i.e. it may share ground with
[[feature-nilpy-multi-arg-callback-bridges]]. **Confirm this before building
on it**; it was read off the source, not measured.

## A cheaper correct step, if the full fix is out of scope

Rejecting an arity-mismatched lambda call turns a silent wrong value into a
diagnostic, which is most of the harm removed for a fraction of the work, and
the "no working CPython program can observe it" escape does not apply here —
`f(3, 4)` is working CPython code that gets a wrong answer. Prefer this over
leaving the silent path in place.

## Gate

Per-fix loop. A `.npy` test covering: too many args, too few args, a
plain-name-defaulted parameter both defaulted and caller-supplied, and a `def`
with the same signature (must stay correct) — diffed against CPython with
`tools/pydiff.py`.

## 2026-08-07 — the silent wrong value is FIXED; the arity DIAGNOSTIC is split out

Two separable defects were filed under one title. The one that made this a
priority — the silently wrong number — is fixed. The loud-diagnostic half is
re-filed as
[[bug-nilpy-a-lambda-call-with-the-wrong-argument-count-does-not-raise]],
with the risk that stopped it from landing here recorded on it.

**Fixed:** a defaulted parameter the caller supplies now overrides the default.
`f = lambda x, y=k: x*y; f(3, 4)` is 12.

**Still open (the new ticket):** `f(1, 2)` on a one-parameter lambda returns 1,
and `f()` returns None, where CPython raises TypeError.

### The root cause, corrected

The hypothesis in the section above was **half wrong, and the wrong half was the
load-bearing one.** It said the bound-fn bridge passes exactly one argument.
It does not: `pyboundfn_callvn` already takes three and honours `NOwn`
(`pyboundfn_setown`), and multi-parameter lambdas (`lambda x, y, z: …`) were
always fine. Nothing here needed
[[feature-nilpy-multi-arg-callback-bridges]] — that dependency was inferred from
reading and would have parked this ticket behind unrelated work.

What is true is the other half: a `name=value` lambda header entry was treated
as a **build-time capture only**, never as a parameter, so it did not count
toward arity and there was nowhere for a caller's argument to land.

### The catch: TWO lowerings, chosen by body SHAPE

`PyLambdaBodyIsLiftable` requires a **call** in the body, so `lambda x, y=k:
x*y` takes the pyeval-closure path while `lambda x, y=k: mul(x, y)` takes the
lifted bound-fn path. Both were broken, differently, and a fix to either alone
looks green against the obvious repro. The test covers both on purpose.

- **Closure path:** the defaulted names are now appended to the closure's
  `Params`, and `PyClosureInvoke` no longer overwrites an unsupplied parameter
  with None when a cap of that name exists — the cap *is* the default. (The
  sibling binding site at the plain interpreted-def call is a fresh scope with
  no caps, so it is unaffected; checked rather than assumed.)
- **Lift path:** `pyboundfn_setdefaults(base, count, varmask)` marks which bound
  slots are defaulted parameters. `pyboundfn_callvn` writes the defaults first
  and lets a supplied argument overwrite them, so "not supplied" needs no
  sentinel. `base` is the caller-side index, deliberately **not** `NOwn`: a
  zero-parameter lambda carries a dummy own parameter the caller never counts,
  so `lambda x=i: x` has `NOwn=1` while `x` is the caller's argument 0.

### Why the corpus decided the design

The one existing user of the idiom, `test/test_nilpy_lambda_capture.npy`, does
`key=lambda v, obj=b, off=offset: off - obj.key_of(v)` — it captures an OBJECT
and calls a method on it. Routing defaulted lambdas to the interpreter (the
smaller change) would have put that through pyeval, which cannot call a compiled
def ([[bug-nilpy-zero-param-lambda-cannot-call-a-def]]). Measuring the corpus
before choosing is what ruled that route out.

`pyeval.pas` is a builtin, but the compiler does not `use` it — so, like
`pylib.pas`, it does **not** trigger the stabilize+pin fixedpoint dance that
`builtin.pas` does. Gate confirmed green without a re-pin.

### Gate

`make compiler/pascal26` (fixedpoint, converged 1 round) + `tools/gate.sh quick`
GREEN. `test_nilpy_lambda_default_override.npy` added, diffed against CPython;
`test_nilpy_lambda_capture.npy` output unchanged.

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.
