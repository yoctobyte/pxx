---
track: N
prio: 45
type: bug
blocked-by: []
commit: PENDING-COMMIT
summary: "A NESTED def with a defaulted parameter ignored the caller's value for it: `def inc(by=1)` inside a function answered inc(2) as if it were inc(). The call bridge clips arguments past the non-defaulted count, and only the LAMBDA lifter ever told it which bound slots are defaults."
---

# A nested def's default parameter wins over the caller's argument

```python
def make():
    n = 0
    def inc(by=1):
        nonlocal n
        n += by
        return n
    return inc

f = make()
print(f(), f(2), f(10))     # CPython 1 3 13     pxx 1 2 3
```

Silent, and on an everyday shape — a counter, an accumulator, any helper with a
tuning parameter. Found 2026-08-15 by a CPython differential sweep of closures;
it was the first line of the probe.

Not limited to `nonlocal`: a nested def with NO captures at all has it too.

```python
def make2():
    def h(a, b=7):
        return (a, b)
    return h
print(make2()(1, 2))        # CPython (1, 2)     pxx (1, 7)
```

## Cause

A nested def taken as a value is LIFTED to a bound-fn: its defaults are
evaluated and bound into slots after the own parameters, and
`pyboundfn_setown(nOwn)` tells the bridge how many leading arguments the caller
supplies. The bridge then CLIPS anything past `nOwn` — so an argument for a
defaulted parameter was dropped and the bound default was used.

The mechanism that fixes this already existed: `pyboundfn_setdefaults(obj,
base, count, varmask)` declares which bound slots are defaulted parameters and
where the caller counts their positions from. Its own comment says it plainly —
"only the lambda lifter calls pyboundfn_setdefaults, so every other bound-fn
user — nested defs, the callback bridges — keeps the lenient behaviour". For the
callback bridges that leniency is deliberate; for a nested def it was simply
missed, and the sibling construct (a lambda with `b=2`) got it right.

`PyNestedDefClosureValue` now chains the same call, with `base = nOwn`, `count =
nDef` (the defaults occupy bound slots 0..nDef-1, bound first) and a varmask
built from the callee's parameter types, exactly as the lambda site builds it.

## Two more bugs found in the same probe, both filed, neither fixed here

- [[bug-nilpy-a-nested-defs-default-is-evaluated-at-value-time-not-def-time]] —
  the default expression is re-evaluated where the def VALUE is built, so
  reassigning the enclosing name between the `def` and the `return` changes it.
  Reproduces on `pinned`, so it predates this fix.
- [[bug-nilpy-a-nested-def-shadowed-by-an-outer-name-binds-to-None]] — naming
  the outer variable the same as the inner def (`g = make3(10)` over `def g`)
  makes the call raise "the name is None". Also pre-existing on `pinned`.

## Gate

`test/test_nilpy_nested_def_default_override.npy` (+`.expected`, in the
Makefile), byte-identical to CPython: one default with `nonlocal`, one with no
captures, TWO defaults (each overridden separately and together), defaults
alongside a capture, a nested def with no defaults as a control, and a nested
def CALLED DIRECTLY rather than returned. `gate.sh quick` GREEN.
