---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`abs(z)` on a complex raises `TypeError: expected a number, got object` where CPython returns the magnitude. Found while writing the parity assertion for `(-8.0) ** 0.5` — `type()`, `.real`, `.imag` and `round()` on a complex all match CPython exactly, so `abs` is the one hole in the set."
---

# `abs()` of a complex raises TypeError

Found 2026-08-16 while resolving
[[bug-n-pow-expected-predates-the-complex-type-and-pxx-differs-from-cpython]].
`abs(z)` was the natural way to assert a complex result without pinning the last
bits of its repr; it does not work.

## Measured

```python
z = (-8.0) ** 0.5
print(type(z).__name__)                        # complex        — matches
print(round(z.real, 12), round(z.imag, 12))    # 0.0 2.828427124746 — matches
print(abs(z))                                  # CPython: 2.8284271247461903
```

| | result |
| --- | --- |
| CPython | `2.8284271247461903` |
| pxx | `Unhandled exception: TypeError: expected a number, got object` |

Every other accessor in that set is already right, so this is one missing arm
rather than a gap in complex support: `abs` reaches a numeric coercion that does
not know the complex object and rejects it as a bare object.

`abs(complex)` is ordinary CPython — it is the documented way to get a magnitude
and appears in any numeric code that ports across. By the standing rule that a
program CPython accepts and runs must work under NilPy, this is a plain defect
rather than a divergence.

## Likely shape of the fix

`abs` needs the same complex arm the other accessors have: return
`hypot(z.real, z.imag)`. Note `pycomplex_pow` already computes exactly that
expression inline (`PyCxSqrt(a.FRe*a.FRe + a.FIm*a.FIm)`), so the helper exists
and wants lifting to a named function rather than a second copy.

## Gate

`abs((-8.0) ** 0.5)` matching CPython, plus `abs(3+4j)` = `5.0` as the exact
control; `make test-nilpy`; self-host fixedpoint.
