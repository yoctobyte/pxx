---
summary: "`{v:g}` in an f-string called FloatToStr instead of the correct PyFmtG that the `%g` operator already used — 1e-5 printed 0.00001, 1e16 printed 10000000000000000.0, 123456.789 printed 123456.789000000004307"
type: bug
prio: 45
track: N
---

# `{v:g}` was str()'s form, not %g — while the correct %g sat one file away

- **Type:** bug (NilPy format specs — `pyformat_of(d: Double; spec)` in
  `compiler/builtin/pylib.pas`). Track N.
- **Status:** done
- **Found:** 2026-08-16, NilPy oracle sweep vs CPython 3 (numeric/formatting
  topic).
- **Shape:** one concept, two implementations, and the second one was wrong —
  `devdocs/dev/normalise-dont-special-case.md`. `PyFmtG` is correct and has
  been all along; the printf-style `%g` operator calls it. The f-string /
  `format()` spec path called `FloatToStr` instead.

## Symptom

| expression | CPython | pxx |
| --- | --- | --- |
| `f"{1e-5:g}"` | `1e-05` | `0.00001` |
| `f"{1e-7:g}"` | `1e-07` | `0.0000001` |
| `f"{1e16:g}"` | `1e+16` | `10000000000000000.0` |
| `f"{123456.789:g}"` | `123457` | `123456.789000000004307` |
| `f"{123456.789:.3}"` | `1.23e+05` | `123456.789` |

`%g` rounds to `prec` SIGNIFICANT digits (default 6) and switches to the
exponential form when the exponent leaves `[-4, prec)`. `FloatToStr` is
str()'s shortest-round-trip form, which answers a different question — and on
the last row it is not even that, because `FloatToStr` is Pascal's fifteen-place
formatter rather than NilPy's own `PyFloatStr` repr.

## Fix

- `g`/`G` with an explicit type char, or with a precision, now calls
  `PyFmtG(d, prec, upper)`.
- A spec naming **no type** (`{v}`, `{v:,}`, `{v:10}`) stays str()-shaped, which
  is CPython's rule — `format(123456.789, '')` is `123456.789`, not `123457` —
  and now uses `PyFloatStr` (NilPy's repr) rather than `FloatToStr`, which is
  what fixed `{v:,}` printing `123,456.789000000004307`.
- A precision with no type char is general format in CPython (`{v:.3}` is
  `{v:.3g}`), so the default kind is now `g` whether or not a precision was
  given; it used to stay on the initial `f` and print fixed-point.

## Gate

`make compiler/pascal26` fixedpoint; `tools/gate.sh quick` GREEN;
`make stabilize-fast && make pin` (v341) because this is a `compiler/builtin`
change; `test/test_nilpy_format_g_spec.npy` — every spec form crossed with
eleven values, plus the no-type rows that must NOT move — matches CPython 3
byte for byte.
