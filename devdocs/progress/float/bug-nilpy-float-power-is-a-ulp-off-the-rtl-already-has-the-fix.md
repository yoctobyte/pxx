---
summary: "NilPy's `**` with a fractional exponent still uses exp(y*ln(x)), so 2**0.5 != math.sqrt(2); lib/rtl/math.pas's Power was fixed with a double-double kernel for exactly these cases and names 2^0.5 in its own comment"
type: bug
prio: 20
track: B+F
---

# `2 ** 0.5` is a ulp off — and the RTL already fixed this exact case

- **Type:** bug (float accuracy — low prio, mechanical, per the standing rule
  that float-handling accuracy bugs are Track B). The code is
  `compiler/builtin/pylib.pas` (`pypow_v`), so landing it needs a re-pin.
- **Status:** backlog
- **Found:** 2026-08-16, NilPy oracle sweep vs CPython 3.
- **Shape:** one concept, two implementations, the second one stale — the same
  pattern as [[bug-nilpy-g-format-spec-is-str-not-percent-g]] found in the same
  sweep. `devdocs/dev/normalise-dont-special-case.md`.

## Symptom

| expression | CPython | pxx |
| --- | --- | --- |
| `2 ** 0.5` | `1.4142135623730951` | `1.414213562373095` |
| `2 ** 1.5` | `2.8284271247461903` | `2.82842712474619` |
| `10 ** 0.5` | `3.1622776601683795` | `3.162277660168379` |
| `2 ** -0.5` | `0.7071067811865476` | `0.7071067811865475` |
| `2 ** 0.5 == math.sqrt(2)` | `True` | **`False`** |

Integer exponents are exact and already right (`2 ** 10.0`, `9 ** 0.5`,
`16 ** 0.25` all agree) — `pypow_v` binary-exponentiates those. Only the
fractional-exponent arm is wrong, and the last row is the one ordinary code
notices: `x ** 0.5` and `math.sqrt(x)` are interchangeable in Python and are
not here.

## Cause and fix

`pypow_v` falls to `PyMathExp(fexp * PyMathLn(fbase))` — three roundings (ln,
the product, exp). `lib/rtl/math.pas`'s `Power` used to be that same expression
and was fixed to carry `y*log(x)` through a double-double kernel; its comment
names `2^0.5` as one of the three cases that motivated it.

So the answer is known and written down — it just lives on the other side of a
dependency wall. pylib must **not** `uses math`: that drags the whole RTL into
every `.npy` (the reason is recorded in pylib's own uses clause). So either

- port `Power` plus the ~22-function `TDd` kernel into `compiler/builtin` (its
  own unit, so pylib and a future consumer share one copy), or
- narrower: implement only the `dd`-precision `exp(y*ln x)` path pylib needs.

The first is more code but leaves ONE implementation of the concept, which is
the point; a third copy of pow is how this ticket gets written again in six
months.

## Gate

A probe sweeping fractional exponents against CPython (the table above plus
`x ** 0.5 == math.sqrt(x)` across a range of x) matches; `gate.sh quick`;
`make stabilize-fast && make pin` since it is a `compiler/builtin` change.
