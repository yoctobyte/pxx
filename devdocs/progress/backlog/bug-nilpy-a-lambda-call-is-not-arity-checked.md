---
track: N
prio: 60
type: bug
summary: "NilPy: a call through a lambda ignores arity — extra arguments are silently DROPPED and missing ones silently become None, so `f = lambda x, y=k: x*y; f(3, 4)` returns 6 instead of 12 with no diagnostic"
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
