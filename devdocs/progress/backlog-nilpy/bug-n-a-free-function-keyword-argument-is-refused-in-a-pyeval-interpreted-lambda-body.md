---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`lambda x: g(x, outside=2.0) <= 5.0` dies at RUN time with `pyeval: unsupported keyword arg: outside`, where `g` is a free function. The discriminator is NOT free-vs-method and NOT the keyword: it is whether the body gets LIFTED. A body that is a bare call (`lambda x: g(x, outside=2.0)`) is compiled and correct; wrapping the same call in a comparison routes the body through pyeval, whose keyword handling is hard-wired to print's `end`/`sep`/`flush` and errors on anything else (compiler/builtin/pyeval.pas:4040). The METHOD spelling of the same shape works through the comparison, which is why this reads as a free-vs-method bug and is not one. Measured 2026-09-12 while clearing the float-literal-in-a-lambda wall; app.py:3305 is the METHOD form and is CORRECT (verified against CPython), so this does NOT block the lekkerzeilen closure. Honest run-time refusal, not a wrong value. A real fix needs the callee's signature at run time so a keyword can be mapped to a parameter slot, which pyeval does not have — that is the actual work, and it is why this is not a microfix."
---

# A free-function keyword argument is refused in a pyeval-interpreted lambda body

## The measured table

All four rows use `def g(x, outside=0.0): return x + outside`:

| body | result |
| --- | --- |
| `lambda x: g(x, outside=2.0)` | OK — `3.0`, CPython's answer |
| `lambda x: g(x, outside=2.0) <= 5.0` | **`pyeval: unsupported keyword arg: outside`** at run time |
| `lambda x: g(x, 2.0) <= 5.0` | OK (positional) |
| `lambda x, z: c.at(x, z, outside=ceiling + 1.0) <= ceiling` | OK — matches CPython |

So the comparison is the discriminator, by way of which path the body takes. The
first and fourth rows are why this was nearly filed as two different bugs.

## Why it is prio 45 and not higher

It cannot produce a wrong value — `EvalError` aborts. And the shape lekkerzeilen
actually contains (app.py:3305) is the method form, which is correct; the closure
is not blocked on this.

## What a fix needs

`ParseCall` in `compiler/builtin/pyeval.pas` collects positional args into a
`TPyList` and has nowhere to put a named one, because at that point it does not
know the callee's parameter names. Either the dynamic call bridge has to accept
named arguments, or pyeval needs the signature. Do not special-case a keyword
name the way `end`/`sep`/`flush` are special-cased — that is the pattern that
produced this gap.
