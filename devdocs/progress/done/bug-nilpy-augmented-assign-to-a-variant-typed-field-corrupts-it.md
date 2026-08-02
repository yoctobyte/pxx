---
track: N
prio: 75
type: bug
summary: "`self.n += x` produces garbage when the field was initialised from an UNANNOTATED ctor parameter — True, an empty line, or 4.94e-323. Annotating the parameter fixes it. This is the most idiomatic shape in Python OO"
status: done
---

# Augmented assignment to a variant-typed field corrupts it

- **Type:** bug (NilPy — SILENT WRONG VALUE, very common shape) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle,
  reduced from a realistic bank-account program.

## Repro

```python
class A:
    def __init__(self, n):        # <-- UNANNOTATED parameter
        self.n = n
    def take(self):
        self.n += 3
        return self.n

print(A(10).take())               # CPython 13
```

| operator | pxx | CPython |
| --- | --- | --- |
| `self.n += 3` | **`True`** | `13` |
| `self.n -= 3` | **empty line / crash** | `7` |
| `self.n *= 3` | **`4.940656458412466e-323`** | `30` |

`4.940656458412466e-323` is decisive: that is the integer 10's bit pattern read
as an IEEE double. The field's value is being reinterpreted through the wrong
representation, which is also what `True` is — a low bit read as a Boolean.

## The controls name the cause exactly

| shape | result |
| --- | --- |
| `def __init__(self, n: int)` — ANNOTATED | **correct** for `+=`, `-=`, `*=` |
| `self.n = 10` in `__init__` — literal, no parameter | **correct** |
| `self.n = self.n - amt` — explicit, not augmented | **correct** |
| `return self.n - amt` — no assignment at all | **correct** |
| `self.n -= amt` then `return 42` | returns 42 — the RETURN is fine |
| **unannotated parameter + augmented assignment** | **wrong** |

So: an unannotated `__init__` parameter is a variant, the field it initialises
becomes variant-typed, and the AUGMENTED-assignment path on a variant field
reads it as a raw scalar instead of unboxing. Plain assignment to the same field
is correct, which is why this hid — the field works everywhere except `+=`.

## Why prio 75

`def __init__(self, n): self.n = n` is the single most common constructor in
Python, annotations are optional and usually absent, and `self.count += 1` is
the most common thing a method does to a field. The failure is silent and the
value is garbage rather than merely stale, so it corrupts arithmetic downstream
rather than announcing itself.

It is also a *class* of bug rather than one operator: `+=`, `-=` and `*=` each
fail differently, which is the signature of an untyped read rather than a
mis-implemented operator.

## Where to look

The augmented-assignment lowering for an `AN_FIELD` target — the same family as
`PyAugBinTok`'s handling in `PyParseStatement`, but on the field path rather than
the local path. Compare what the explicit `self.n = self.n - amt` form builds
(correct) against what `self.n -= amt` builds: the explicit form goes through the
ordinary variant-aware binop, so the difference is likely a hand-built binop on
the augmented path that skips the unbox the runtime helpers do.

`PXXDBG=a.ast:A.take` on both spellings answers this in one run, and
[[project_nilpy_static_vs_variant_operand_paths_diverge]] is the same shape one
level up — measure before theorising.

## Gate

A `.npy` diffed against CPython: `+=`, `-=`, `*=`, `//=`, `%=` on a field from an
unannotated ctor parameter; the annotated and literal-initialised controls; a
string field with `+=`; a list field with `+=`; the same operators on a plain
LOCAL variable (which should be unaffected); and a field mutated across several
method calls to confirm the value accumulates rather than only the first one
landing.

## Log
- 2026-08-02 — resolved, commit 90eb6a85e.
