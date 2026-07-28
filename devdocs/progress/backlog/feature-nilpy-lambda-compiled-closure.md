---
summary: "nilpy: lambdas are interpreted by pyeval — compile them like nested defs (perf + one semantics)"
type: feature
track: N
prio: 45
---

# A lambda's body runs in pyeval, interpreted from its source text

- **Type:** feature (Nil-Python frontend) — **Track N**
- **Opened:** 2026-07-28, the wall `settings.py` stops at once it is BUILT.

## CORRECTED (2026-07-28, same day)

The first diagnosis here — "pyeval cannot call our methods" — was WRONG. It can:
`PyHostCall` reads the instance's class RTTI, finds the method by name and
marshals by arity and kind, so a lambda that captures a widget and calls a method
on it works today:

```python
v.trace_add("write", lambda *a: print(v.get()))        # works
v.trace_add("write", lambda *a, var=v: print(var.get()))   # used to fail
```

The real gap was narrow and is FIXED: a lambda's own DEFAULT PARAMETERS
(`key=key`, `var=var` — Python's idiom for pinning a loop variable) were parsed
as ordinary parameters and their values discarded, so the name was unbound at
invoke time and the method call landed on nothing. They are now bound as
build-time captures, exactly as the nested-def path already binds its
default-arg expressions. Test: `test/test_nilpy_lambda_capture.npy`.

What remains below is the LONG-TERM item, and it is about performance and having
ONE implementation of Python semantics — not about a missing capability.

## What breaks

```python
var.trace_add("write", lambda *args, key=key, var=var: self.update_setting(section, key, var))
```

A `lambda` is lowered to a pyeval CLOSURE built from the body's SOURCE TEXT
(`pyclosure_src_new`), so every invocation re-runs an interpreter over it. That
costs speed in a hot path (`sorted(key=...)`, a GUI callback per event), and it
means Python semantics exist TWICE in this project — once in the compiler, once
in pyeval — which is the kind of duplication that drifts.

It also limits what a body may contain: `PyLambdaTokText` reconstructs the source
from a token span and refuses anything exotic.

## Two ways out

1. **Compile the lambda like a nested def** (recommended). NilPy already lifts a
   captures-only nested `def` into a REAL proc with its captures bound
   (`pyboundfn_new` / `pyboundfn_bind_var`), and compiled code calls methods
   natively. A lambda is a nested def with one expression body, so the same
   lifting applies; keep the pyeval path as the fallback for bodies the lifter
   rejects. This also makes lambdas faster and removes a whole class of "not
   supported in a lambda body yet" errors.
2. **Register compiled classes with pyeval's host trampoline** — a runtime
   method table (name → proc address) per class, emitted by the compiler. More
   machinery, and it keeps the interpreter in the hot path.

## Gate

`make test-nilpy` with a case that captures an object and calls a method on it
from a lambda, CPython-diffed; and songformatter's `settings.py` populating its
frame under Xvfb.
