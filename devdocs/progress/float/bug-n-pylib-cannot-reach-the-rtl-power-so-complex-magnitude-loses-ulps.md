---
track: N+F
prio: 25
type: bug
blocked-by: []
summary: "`pycomplex_pow` computes |z|**b as exp(b*ln|z|) — two roundings — where CPython calls pow() directly, so `(-8.0) ** 0.5` gives an imaginary part of 2.8284271247461894 against CPython's 2.8284271247461903 (~4 ulp). The cause is structural: pylib lives in compiler/builtin and cannot reach the RTL's correctly-rounded Power, which is why it carries its own series ln/exp in the first place."
---

# pylib cannot reach the RTL's Power, so complex magnitudes lose a few ulp

Split out 2026-08-16 from
[[bug-n-pow-expected-predates-the-complex-type-and-pxx-differs-from-cpython]],
whose main defect (a `-0` real part from a cancelling argument reduction) is
fixed. This is the residual, and it is an ARCHITECTURE question rather than a
numerics tweak, which is why it is not folded in.

## Measured, after the quadrant-boundary fix

| expression | CPython | pxx |
| --- | --- | --- |
| `(-4) ** 0.5` | `(1.2246467991473532e-16+2j)` | **exact match** |
| `(-1) ** 0.5` | `(6.123233995736766e-17+1j)` | **exact match** |
| `(-8.0) ** 0.5` | `…+2.8284271247461903j` | `…+2.8284271247461894j` |
| `(-8) ** (1/3)` | `1.0000000000000002+1.7320508075688772j` | `1.0000000000000002+1.7320508075688767j` |

Real parts are now right everywhere. What remains is the MAGNITUDE.

## Cause

`pycomplex_pow` computes `z**w = exp(w * ln z)`:

```pascal
lnr := PyMathLn(PyCxSqrt(a.FRe*a.FRe + a.FIm*a.FIm));
...
m := PyMathExp(xr);
```

CPython's `_Py_c_pow` instead computes `len = pow(vabs, b.real)` — one
correctly-rounded call where pxx takes a logarithm and an exponential, each
rounded, on top of pylib's own series implementations of both. For `(-8.0)**0.5`
that is `exp(0.5*ln 8)` versus `pow(8, 0.5)`, and the difference is the ~4 ulp
above.

**Why it is not simply fixed:** `compiler/builtin/pylib.pas` uses
`builtin, exceptions, pypal, promocore, typinfo` — it cannot see `lib/rtl/math.pas`,
where the correctly-rounded `Power`, `Sqrt`, `Sin` and `Cos` live. That boundary
is exactly why pylib carries `PyMathLn`, `PyMathExp`, `PyCxSqrt` and
`PyCxCosSin` as its own series implementations. A NilPy program calling
`math.cos` gets the good one by name match; complex arithmetic inside pylib gets
the local copy. `builtin` has no trig at all, so there is nowhere better to
reach today.

## The fork, which is why this is filed rather than patched

1. **Write a correctly-rounded `pow` inside pylib.** Closes the rows, and makes
   a THIRD implementation of the same function in the tree. Against the standing
   rule about counting mechanisms per concept.
2. **Let `compiler/builtin` reach the RTL's numerics**, or hoist the
   correctly-rounded kernels somewhere both can see. Deletes the duplicates
   rather than adding one, and would also fix `PyCxArcTan` and the series
   `PyMathLn`/`PyMathExp` at the same time — but it moves a boundary that the
   self-host bootstrap depends on, so it is a Track A design call.
3. **Accept it.** A few ulp on the magnitude of a complex power is the
   low-priority mechanical accuracy class by the standing rule, and no test now
   asserts those digits.

Recommendation: **(3) for now, (2) whenever the builtin/RTL numerics boundary is
revisited for another reason** — the win then is several duplicate kernels
deleted, not this one row.

## Note

`test_nilpy_pow_matches_cpython.npy` deliberately asserts this value to 12
decimals rather than by repr, with the reason in the test, so nothing is
silently pinned to the current ulps.

## Gate

Whichever option is taken: the four rows above matching CPython, `make
test-nilpy`, self-host fixedpoint.
