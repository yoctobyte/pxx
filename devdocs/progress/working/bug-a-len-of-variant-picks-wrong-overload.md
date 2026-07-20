---
track: A
prio: 55
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

## Wider than `len` — confirmed 2026-07-20 by the operator sweep

The same shape hit two more operators once the rest of the NilPy semantics
landed (commit a123c875 and follow-up). Both involve a for-in loop variable,
which is ALWAYS a variant, so these are ordinary Python, not corner cases:

```python
for s in ["ab"]:
    print(s * 2)     # CPython abab -> pxx a POINTER
    print(len(s))    # CPython 2    -> pxx SEGFAULT
```

`v * 2` is the interesting one and is NOT just a missing unbox: it is
genuinely ambiguous at lowering time. If the payload is a string Python
REPEATS, if it is a number Python MULTIPLIES. A speculative "treat a variant
operand of `*` as a string" hook was written and reverted during that session
for exactly this reason -- it would have miscompiled `v * 2` on an int.

The honest fix is one runtime-dispatching multiply (`pymul_v`) alongside the
`pyfloordiv_v` / `pyfloormod_v` pair that DID land, since `//` and `%` are
unambiguous (numeric tags only, string is an error) while `*` is not.
`builtinheap`'s existing variant binop already dispatches arithmetic on tags
and is the natural place, but it is shared with Pascal variants -- decide
whether string-repeat belongs there or in a NilPy-only helper.

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

## MOSTLY FIXED 2026-07-20 (commit 31fcd497)

`len`, `ord` and `*` on a variant now dispatch at runtime via pylib
`pylen_v` / `pyord_v` / `pymul_v` — including `len()` of a nested list, dict
or bytearray, resolved with closed-world `is` on the VT_OBJECT payload.
Covered by `test/test_nilpy_variant_polymorphic_builtins.npy`, diffed against
CPython.

Two seams were required, and missing the second is why a first attempt only
half-worked: **`len` resolves to a PROC, `ord` is an INTRINSIC** (AN_CALL with
a negative ASTIVal) dispatched earlier in `IRLowerAST` and never reaching the
proc-name hook. Any further builtin needs checking against BOTH.

## Still open: `abs(v)` — and the reason is worth recording

`abs` is a parser SOFT-ALIAS to `__pxxAbsInt` / `__pxxAbsDbl`, and the alias
picks Int vs Dbl by STATIC type, which a variant cannot answer. A `pyabs_v`
returning a **Variant** was written and works standalone:

```python
for a in [7]:
    print(abs(a))          # 7, correct
```

but breaks as soon as a second variant-producing expression shares the
statement:

```python
    print(abs(a), -a)      # dies
```

Notably this is NOT a general limitation — two Variant-returning helpers do
coexist fine (`print(a//2, a%2)` is correct), so `pyfloordiv_v`'s marshalling
differs from what the builtin-redirect seam produces. Neither `IRVariantAddr`
nor `IRLowerCallArg` for the argument fixed it, so the difference is in how
the RESULT's hidden destination is allocated, not the argument.

`pyabs_v` was removed rather than shipped half-working. Reproduce with the two
lines above; the `//` path is the working oracle to diff the emitted call
against.

Remaining untested against a variant argument: `min`, `max`, `bool`, `list`,
`chr`. Sweep them the same way before closing.

