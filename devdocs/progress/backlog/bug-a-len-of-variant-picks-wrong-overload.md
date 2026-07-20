---
track: A
prio: 70
type: bug
---

# `len(v)` on a Variant segfaults — a polymorphic builtin cannot pick an overload statically

Split out of [[bug-a-nilpy-variant-element-not-usable-as-scalar]] while
landing the variant unbox (commit 8bd1ac4c). **Not** the missing-unbox bug —
that is fixed; this is a distinct root cause and was left unfixed
deliberately.

## Repro

```python
ss = ["ab"]
d = ss[0]
print(len(d))     # CPython 2  -> pxx SEGFAULT
```

Compiles clean, dies at runtime.

## Root cause

`len` is an OVERLOAD SET in pylib — `len(TPyList)`, `len(TPyDict)`,
`len(TPyBytes)`, `len(const AnsiString)`. The argument here is a `Variant`,
which matches none of them, so resolution picks a wrong one (the handle/tag
is then dereferenced as a list). CPython dispatches `len` on the RUNTIME
type; pxx picks at compile time.

The variant-unbox work does not reach this: unboxing needs a single target
kind, and which one is right depends on the tag at runtime. Widening the
unbox to guess would turn a crash into a silent wrong answer — strictly
worse.

## Shape

A `len(const v: Variant): Integer` overload in pylib that switches on the
tag (VT_STRING -> byte length, and the object tags -> list/dict count) and
raises a Python-shaped TypeError for the rest. Same treatment likely needed
for the other polymorphic builtins over a variant argument: `min`, `max`,
`abs`, `bool`, `list`, `ord`. Worth sweeping the whole builtin table against
CPython with a variant argument rather than fixing `len` alone —
[[feedback_sweep_operators_against_oracle_not_just_features]].

Note the pylib routine itself is Track B/N ground; the overload-resolution
half (should a Variant argument prefer a Variant overload before any other?)
is Track A. File the split when picking this up.

## Gate

`make test` + self-host byte-identical, `test-nilpy` green, and the repro
plus a variant-argument sweep of the builtin table matching CPython.
