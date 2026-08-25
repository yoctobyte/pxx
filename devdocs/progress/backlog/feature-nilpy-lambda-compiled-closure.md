---
summary: "nilpy: lambdas are interpreted by pyeval — compile them like nested defs (perf + one semantics)"
type: feature
track: N
prio: 55
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


## SLICE ONE LANDED (2026-07-28) — a call-shaped lambda is COMPILED

A lambda whose body is a CALL (`lambda event: self.canvas.configure(
scrollregion=self.canvas.bbox("all"))`, `lambda e: handler(e.width)`) and which
has exactly one own parameter is now LIFTED into a real proc:

- the header's own parameter becomes a variant param, every enclosing local or
  parameter the body mentions (above all `self`) becomes a trailing capture
  bound at build time, and the value is the same `pyboundfn_new` object the
  nested-def path already produces — so the callback bridge dispatches it with
  no new machinery;
- the body is queued like a nested def's and compiled once the enclosing routine
  is complete (`PyCompileLambdaBody`, drained in `PyParseDef`, `PyParseMethod`
  and at module level).

What that buys, beyond speed: keyword arguments now bind BY NAME against the
real signature. Through pyeval they were appended POSITIONALLY
([[bug-nilpy-pyeval-host-kwargs-positional]]), so `configure(scrollregion=X)`
set `-state` instead — silently. And the five-argument cap on pyeval's host-call
trampoline no longer applies to a lifted body.

### Deliberately still on pyeval

- a body that is not a call — `key=lambda p: p[1]` — because the bound-fn bridge
  DISCARDS the callee's result, and a lambda whose value a caller reads must
  return one. Lifting those needs the bridge to carry a result back;
- more than one own parameter (`lambda a, b: ...`), and `*args` forms;
- anything the shape test rejects, which keeps the fallback total.

Three traps worth recording, each cost real time:

1. `AllocParam` seeds a symbol's `RecName` from `LastTypeRecId` — whatever type
   the parser last saw ANYWHERE. A body compiled far from its header inherited a
   stale class id, and `event.width` reported "no such member" instead of a
   dynamic attribute read. Set the class identity explicitly, or clear it.
2. `PyExprMode` must be ON while the body parses. The module-level drain runs
   after `ParsePyProgram` turns it off, and without it a `.name` read off a
   variant fell through to a raw field read at offset 0 — it printed the
   variant's TYPE TAG (7) as the attribute's value.
3. The expression must be wrapped in an `AN_BLOCK` (and hoisted temporaries
   flushed) before `CompileAST`, exactly as every other body path hands it one;
   a bare expression node compiled to nothing at all, silently.

Test: `examples/tk/callbacks.npy` (lifted lambda calling a method on `self`).
Gate: `make test-nilpy` green, self-host fixedpoint byte-identical,
`testmgr --tier quick` green.
