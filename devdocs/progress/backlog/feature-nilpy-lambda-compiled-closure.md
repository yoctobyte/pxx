---
summary: "nilpy: a lambda cannot call a method on a captured object — compile lambdas like nested defs"
type: feature
track: N
prio: 65
---

# A lambda's body runs in pyeval, which cannot call our methods

- **Type:** feature (Nil-Python frontend) — **Track N**
- **Opened:** 2026-07-28, the wall `settings.py` stops at once it is BUILT.

## What breaks

```python
var.trace_add("write", lambda *args, key=key, var=var: self.update_setting(section, key, var))
```

The callback fires (the Tk callback mechanism works — see
[[feature-nilpy-tk-callbacks]], landed), and then:

```
pyeval: cannot call method get on this value
```

A `lambda` is lowered to a pyeval CLOSURE built from the body's source text
(`pyclosure_src_new`), and the interpreter can only call methods on the types it
knows (list, dict, str, bytes) plus a host trampoline that our compiled classes
are not registered with. Every captured object — a `BooleanVar`, `self`, any
widget — is opaque to it.

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
