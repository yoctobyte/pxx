---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`f(**d)` — unpacking a dict into a call — is a PARSE error (\"expected expression\") for every callee shape: a plain def, a **kwargs def, a method, a constructor. Only the forwarding shape `f(*args, **kwargs)` inside a def that declares them works."
---

# A dict cannot be unpacked into a call

Found 2026-08-16 by a `tools/pydiff.py` sweep, not by a report.

## Measured — the boundary is "is it the enclosing def's own star pair"

```python
def f(a=1, b=2): return (a, b)
d = {"a": 5, "b": 6}
f(**d)                     # pascal26: error: expected expression   near: f >>> d

def g(**kw): return kw
g(**d)                     # same

class C:
    def __init__(self, **kw): self.n = len(kw)
C(**d)                     # same
C().m(**d)                 # same

def fwd(*args, **kwargs):
    return f(*args, **kwargs)   # WORKS — the one supported shape
```

So the star pair is only understood when it names the enclosing def's own
collectors, which is what `PyStarForwardCall` was built for. An ordinary dict
is not accepted anywhere.

## Why it matters

`f(**opts)` is one of Python's core call forms — config dicts, argparse
namespaces, `dict(**base, extra=1)`, every wrapper that passes options
through. And the failure is a PARSE error naming neither the star nor the
callee, so it reads as a syntax problem in the user's code.

## Design — the callee's parameters are known, so this can be a desugar

The machinery is nearly all there. `PyStarForwardCall` already desugars
`f(*args)` into a dispatch over the arities the callee accepts, and refuses
keyword forwarding with the comment *"binding a runtime dict onto named
parameters needs a call protocol NilPy does not have"*. That is true of the
GENERAL case and not of this one: at a call site the callee is known, so its
parameter names are known, and `f(**d)` can lower to

```
    pystar_check_kwnames(d, "a", "b", ...)      (hoisted; refuses an unknown key
                                                 exactly as CPython's TypeError does)
    f(a := d.get("a", <default a>), b := d.get("b", <default b>), ...)
```

with a required parameter's missing key raising rather than defaulting. That is
the same shape the positional forwarder uses, one level simpler because there
is no arity dispatch — the slot count is fixed.

Mixed `f(x, **d)` and `f(**d, y=1)` fall out of the same lowering: the
explicitly-written arguments win their slots and the dict fills the rest.

The genuinely hard case stays refused: a callee that is a VALUE (a variable
holding a function) has no known parameter list, so `cb(**d)` there needs the
runtime protocol and should say so by name.

## Gate

A `.npy` diffed against CPython covering: a plain def, a defaulted def with a
partial dict, a `**kwargs` def, a method, a constructor, the mixed forms, an
unknown key (TypeError), and a missing required key (TypeError). Plus the
per-fix loop.
