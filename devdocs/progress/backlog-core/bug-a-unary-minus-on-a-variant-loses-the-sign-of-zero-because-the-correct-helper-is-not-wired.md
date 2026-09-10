---
slug: bug-a-unary-minus-on-a-variant-loses-the-sign-of-zero-because-the-correct-helper-is-not-wired
track: A
prio: 35
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [variant, float, negative-zero, half-wired-door, nilpy]
blocked-by: []
summary: "`-v` where `v` is a Variant holding +0.0 answers +0.0; the same expression on a plain Double answers -0.0, and pylib's own `pyneg_v(v)` -- called by hand on the same Variant -- also answers -0.0. So the correct helper EXISTS and the lowering does not call it: Variant unary minus is evidently going through a subtraction from zero, where IEEE gives 0 - 0 = +0. Measured in Pascal (three rows, one program) and inherited by NilPy, where it splits by expression shape exactly as the Variant boundary predicts: `-x` on a local or a literal or a `self.f` or a `def f(a: float)` parameter is CORRECT, and `-lst[0]`, `-tup[0]`, `-dct[k]` and `-a` in an UNTYPED def are all wrong. atan2's quadrant answers depend on it: CPython's `math.atan2(-0.0, 1.0)` is -0.0 and ours is +0.0 wherever the argument arrives through a Variant."
---

# Measured 2026-09-10, compiler `pascal26` at HEAD

## The three rows that name the defect

```pascal
var d: Double; v, w: Variant;
d := 0.0;   writeln(bits(-d));            { 8000000000000000  correct }
v := 0.0;   w := -v;  writeln(bits(w));   { 0000000000000000  WRONG   }
            w := pyneg_v(v); writeln(...); { 8000000000000000  correct }
```

One program, one run. `pyneg_v` in `compiler/builtin/pylib.pas:9834` does the
right thing — it tests `PyVarIsFloat` and writes `-PyVarAsFloat(p)` — and the
compiler is not routing `-v` to it. `0.0 - 0.0` is `+0.0` in IEEE 754, which is
exactly the answer observed, so the lowering is a subtraction.

**This is the half-wired-door shape**: the door exists, it is correct, and the
committed path does not use it. It does not fail by refusing; it fails by
answering.

## The NilPy split, which is the same fact seen from the frontend

| expression | result |
| --- | --- |
| `-v` for a local `v = 0.0` | correct, `-0.0` |
| `-(0.0)` literal | correct |
| `-c.f` for a declared float attribute | correct |
| `-a` in `def g(a: float)` | correct |
| `-a` in `def h(a)` — untyped | **wrong, `+0.0`** |
| `-lst[0]` | **wrong** |
| `-tup[0]` | **wrong** |
| `-dct["k"]` | **wrong** |

The typed/untyped parameter pair is the control: same syntax, same value, and
the only thing that differs is whether the operand is a Variant.

## Why it is not prio 20

Signed zero is not decoration in the one place it is most likely to be read
through a Variant. `atan2` sends `+0` and `-0` to opposite sides of the axis —
`lib/rtl/math.pas`'s `ArcTan2` has a comment about exactly that, and its own
signed-zero rows are asserted — so `math.atan2(-0.0, 1.0)` is `-0.0` in CPython
and `+0.0` here as soon as the argument reaches the call through a list, a
tuple, a dict or an untyped parameter, which is how a Python program normally
holds a number. `copysign`, `1/x` and any sign-of-zero test inherit it too.

It stays at 35 rather than higher because a program that CARES about the sign
of zero and holds the value in a Variant is rare, and no corpus site is known
to hit it.

## How it was found

Building `test/test_nilpy_math_atan_and_atan2_bit_for_bit.npy`
([[bug-b-arctan-answers-nan-above-1e300-which-is-why-math-atan2-is-still-refused]]).
A row wrote `math.atan(-x)` while looping `for x in xs`, and the `x = 0.0`
iteration disagreed with CPython. The test now writes every sign out longhand
and records the absence in its header rather than asserting a known divergence
against a CPython-generated oracle.
