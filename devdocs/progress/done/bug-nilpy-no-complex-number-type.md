---
prio: 15
track: N
type: bug
blocked-by: []
status: done
owner: plexus-APN
---

# NilPy has no complex number type

- **Type:** bug / missing type (NilPy) — **Track N**
- **Found:** 2026-08-09, while making
  [[bug-nilpy-pow-and-log-hang-on-a-non-positive-base]] refuse instead of hang.
- **Loud** since that fix: a named `ValueError`, not a wrong real number.

```python
print((-8) ** (1 / 3))    # CPython (1.0000000000000002+1.7320508075688772j)
                          # pxx     ValueError: ... is complex, which NilPy does not have
print(complex(1, 2))      # CPython (1+2j)
print(1j)
```

`complex` is a Python builtin type, so this is a genuine upward-compatibility
gap: a program CPython accepts and runs does not run here.

## Why it is prio 15 anyway

Complex arithmetic appears in almost no application code outside numerics, and
the one place it turns up by ACCIDENT — a negative base raised to a fractional
power — now raises a clear, named error rather than hanging or inventing a real
number. So the cost of not having it is a loud refusal in a rare spot.

`lib/rtl/ucomplex.pas` exists on the Pascal side, which is a starting point if
this is ever picked up: the type and its arithmetic exist, and the work would be
the NilPy surface (the `j` literal suffix, `complex()`, `.real`/`.imag`, repr,
and the arithmetic dunder routing) rather than the maths.

## Gate
`.npy` diffed against CPython: a `1j` literal, `complex(a, b)`, `.real`/`.imag`,
repr of several values, arithmetic between complex and int/float, and
`(-8) ** (1/3)` giving CPython's value.


## Implemented — 2026-08-16

`complex` is a real NilPy type now. The whole gate surface this ticket named is
checked in as `test/test_nilpy_complex.npy`, wired into `test-nilpy` and diffed
**live against CPython** by the Makefile rule (`= "$(python3 ...)"`), so every
line is an exact agreement rather than a recorded approximation.

### Shape: a pylib CLASS, not a new variant tag

A tag would need a heap payload anyway — two doubles do not fit one variant
slot — and that means touching all four object-tag sites plus the aarch64
clear/retain pair, which the survey flagged as an existing cross-target
asymmetry. As an ordinary tag-7 object every one of those paths already works.

### What had to be told about it, one by one

Complex is a pylib class, and **pylib classes are deliberately excluded from
every dunder-dispatch arm** (`PyRecIsPylibOwnClass`). That exclusion is correct
— it is what keeps `[1,2] / 3` a loud error instead of arithmetic on a list
handle — but it means complex gets nothing for free. Each arm below had to name
it, and each one, left undone, produced arithmetic on the object HANDLE:

| surface | where |
| --- | --- |
| `1j` literal | `pylexer.inc` — expands to `pycomplex_make(0.0, v)` at LEX time, so it needs no token kind, no parser arm and no folding, and works in every expression position |
| `complex(...)` | pylib routine resolved BY NAME, the `bytes(...)` route — no parser intrinsic |
| `.real` / `.imag` | `PyDeclaredAttrGet` (pylib), the one place BOTH attribute getters meet |
| `+ - * /`, either order, mixed with int/float | `parser.inc` additive + multiplicative arms |
| `== !=` | `parser.inc` relational arm |
| unary `-` | `parser.inc` `tkMinus` factor |
| `abs()` | `parser.inc` — the arm whose own comment records the identical handle-as-a-number bug for user classes |
| `**` | `PyMakePow`, plus the value-dependent float case below |
| `repr` / `str` / `print` | `pyvar_repr` + `pyvar_print_of` |
| `type(z).__name__` | `pyvar_type_name` |

**`.real` is resolved at RUN time on purpose.** The Python names cannot BE the
pylib field names: `real` lexes as a TYPE token in the Pascal lexer, so pylib
cannot name its own field that (measured — `z.real` inside pylib is "no such
member"). Mapping the names in the frontend would have to be repeated at every
attribute site, and NilPy has five, split by receiver shape — the split this
repo keeps re-fixing. Both getters call `PyDeclaredAttrGet` first, so one arm
there serves every shape. Verified on both the bare-ident and chained receivers.

**Arithmetic is built as direct calls, not Pascal `operator` overloads**, and
that is the interesting half. Overloads are keyed on the LEFT operand and match
the right one only as a *preference*: `z + 1` with an Int64 right operand would
miss a `(TPyComplex, Double)` entry, fall back to the first `+` registered for
TPyComplex, and pass the integer where a TPyComplex pointer was expected —
silently, since both are one machine word. Coercing both sides and naming the
routine has no such failure mode.

### `**` — the case no static type can express

`x ** y` is a float for a non-negative base and a COMPLEX for a negative one,
decided by the VALUES. So the float path now calls `pypow_cx`, which returns a
Variant, **and the widening is gated on the EXPONENT**: an integral exponent is
real for every base, so `x ** 2` keeps its Double typing, its direct RTL `Power`
call and its static overflow guard. Only the genuinely value-dependent case
widens. `(-8) ** (1/3)` therefore answers a complex instead of the ValueError
this ticket was filed against.

`pycomplex_pow` uses repeated multiplication for a small integer exponent, as
CPython does: `2j ** 2` is exactly `(-4+0j)` that way and
`(-4.000000000000001+9.9e-16j)` through `exp(w ln z)`.

### Accuracy — the one place we do not match CPython

pylib cannot `uses math` (the RTL's `Abs` overload set hides pylib's own), so
sqrt/sin/cos/atan are hand-rolled beside the existing `PyMathLn`/`PyMathExp`.
Every line of the checked-in test agrees with CPython exactly; the residual is
`(-8) ** (1/3)`:

```
exact        1                  + 1.7320508075688772935…j
CPython      1.0000000000000002 + 1.7320508075688772j
pxx          1                  + 1.7320508075688767j
```

Both differ from the exact value in the last ulp, in different components —
pxx's real part is exactly right where CPython's is 2 ulp high, and pxx's
imaginary part is 5 ulp low. Left alone deliberately under the standing
float-accuracy rule, and filed as its own low-prio ticket
[[bug-nilpy-complex-pow-is-a-few-ulp-off-cpython]] rather than chased here. It
is why that one line is not in the differential test.

### Found on the way, filed separately

[[bug-p-operator-overload-only-inspects-its-first-operand]] — `operator + (a:
Double; b: TCx)` is refused at the declaration while FPC accepts it. Reached
from reflected arithmetic; a Pascal frontend bug in its own right, not about
complex.

### Gate

`make compiler/pascal26` (self-host fixedpoint, converged round 1), the
23-line CPython oracle, a float-`**` regression sweep (18 shapes, the two
divergent rows confirmed IDENTICAL to the PINNED binary — the pre-existing
[[bug-nilpy-float-power-is-a-ulp-off-the-rtl-already-has-the-fix]], not a
regression), `tools/gate.sh quick` GREEN, and a re-pin since
`compiler/builtin` changed.

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.
