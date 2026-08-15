---
track: N
prio: 30
type: bug
blocked-by: []
summary: "A nested def's default expression is re-evaluated where the def VALUE is built, not at the `def` statement — so reassigning the enclosing name in between changes the default. CPython evaluates it once, at def time."
---

# A nested def's default is evaluated at value time

```python
def make():
    seed = 5
    def h(v=seed):
        return v
    seed = 99
    return h

print(make()())          # CPython 5     pxx 99
```

Silent. Reproduces on `pinned` (v327) and at HEAD; found 2026-08-15 alongside
[[bug-nilpy-a-nested-defs-default-parameter-ignores-the-callers-value]], which
is a different half of the same lowering and is fixed.

## Cause

`PyNestedDefClosureValue` re-parses each default expression and binds it where
the def is taken AS A VALUE (`return h`), not at the `def` statement. Its own
comment claims the opposite — "its default expression re-parsed HERE, in the
scope where the def statement stands — Python's default-at-def-time rule" —
which is true about the SCOPE and false about the TIME.

Note the shape it was written for: uforth's `DOES>`/`DEFER` idiom deliberately
wants per-invocation binding of the ENCLOSING call, and that is what this
gives. So the fix is not "move it earlier" without checking that corpus — it is
to bind at the `def` statement into a hidden slot the value build then reads,
which is what CPython does and what still gives DOES> a fresh value per
enclosing invocation.

## Gate

`.npy` diffed against CPython: reassignment between the `def` and the return; a
default reading a parameter of the enclosing def; two defaults where only one is
reassigned; a def value taken twice from one enclosing call; and the uforth
DOES>-shaped case (a fresh enclosing invocation gives a fresh default).
