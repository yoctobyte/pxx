---
summary: "`(-8) ** (1/3)` answers a complex now, but its imaginary part is 5 ulp low: pylib cannot `uses math`, so complex pow rides hand-rolled sqrt/sin/cos beside PyMathLn/PyMathExp. Every other line of the complex oracle matches CPython exactly."
type: bug
prio: 20
track: B+F
blocked-by: []
---

# Complex `**` is a few ulp off CPython

- **Type:** bug (float accuracy — low prio, mechanical, per the standing rule
  that float-handling accuracy bugs are Track B). The code is
  `compiler/builtin/pylib.pas`, so landing it needs a re-pin.
- **Found:** 2026-08-16, implementing
  [[bug-nilpy-no-complex-number-type]]. It is the one line of that ticket's
  CPython oracle that does not agree, which is why it is not in the checked-in
  differential test.

## Measured

```
             (-8) ** (1/3)
exact        1                  + 1.7320508075688772935…j
CPython      1.0000000000000002 + 1.7320508075688772j
pxx          1                  + 1.7320508075688767j
```

Note which way each errs: **pxx's real part is exactly right and CPython's is
2 ulp high**; pxx's imaginary part is 5 ulp low. So this is not "pxx is wrong
and CPython is right" — both are last-ulp approximations of the same exact
value, and they disagree. What we owe is CPython's answer, because NilPy's
contract is upward compatibility with it, not mathematical optimality.

Everything else in the complex surface matches CPython exactly — all three repr
shapes, every arithmetic form, `abs`, `==`, and integer-exponent `**` (which
takes the repeated-multiplication path CPython also uses, so `2j ** 2` is
exactly `(-4+0j)`).

## Cause

`pycomplex_pow` computes the principal branch `exp(w · ln z)`, needing
`ln`, `exp`, `sqrt`, `sin`, `cos` and `atan2`. **pylib cannot `uses math`** —
the RTL's `Abs` overload set hides pylib's own, so `abs(2.5)` stops resolving
(measured 2026-08-16, recorded beside `PyPowHook`). So sqrt/sin/cos/atan are
hand-rolled next to the existing `PyMathLn`/`PyMathExp`, with quadrant
reduction and a 12-term Taylor pair. Good to a few ulp; not correctly rounded.

## Fix shape

The sanctioned way around the dependency wall already exists and is already
used by this exact operator: **the hook pattern**. The frontend auto-`uses
math` whenever it sees `**` and installs `@Power` into `PyPowHook`
(`pyparser.inc`, `PyPowHook` in `pylib.pas`). Complex pow needs the same for
`Sqrt`, `Sin`, `Cos` and `ArcTan2`, whose RTL versions are correctly rounded —
four more hooks installed at the same site, with the hand-rolled series staying
as the fallback for a program that pulls no math unit.

That is mechanical, and it would also let `pycomplex_abs` use the RTL's `Hypot`
rather than `sqrt(re²+im²)`, which overflows for large components where CPython
does not — worth folding into the same pass.

Sibling of [[bug-nilpy-float-power-is-a-ulp-off-the-rtl-already-has-the-fix]]:
same wall, same answer already written down on the other side of it.

## Gate

The `(-8) ** (1/3)` row added to `test/test_nilpy_complex.npy` (which is diffed
live against CPython, so it needs no separate `.expected`), plus a sweep of
fractional and complex exponents; `gate.sh quick`; `make stabilize-fast &&
make pin`.
