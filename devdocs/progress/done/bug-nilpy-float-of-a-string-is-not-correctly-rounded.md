---
track: N
prio: 55
type: bug
summary: "`float(\"1e308\")` is not the same double as the literal `1e308`. pyfloat_parse reconstructs with FLOAT arithmetic (intPart/frac/scale as Doubles), so it is not correctly rounded — 3 of 6 hard inputs disagree with pxx's own literals. Silent: the value is close, just not the right double."
status: done
owner: claude-AN
---

# `float(str)` is not correctly rounded

- **Type:** bug (NilPy — silent wrong value) — **Track N**
- **Found:** 2026-08-03, while sizing
  [[bug-nilpy-float-repr-is-not-pythons-shortest-roundtrip]]. Distinct defect;
  filed separately because it is user-visible on its own and would otherwise be
  lost if that ticket's parser copy were skipped as "just for the round-trip
  check".

## Measured

Each line compares `float("...")` against **pxx's own literal** for the same
text. The literals are correct (verified separately against CPython), so a
`False` is `pyfloat_parse` being wrong:

```python
float("0.1")                    == 0.1                       -> True
float("1e308")                  == 1e308                     -> False
float("2.2250738585072011e-308")== 2.2250738585072011e-308   -> False
float("123456789.123456789")    == 123456789.123456789       -> True
float("0.3333333333333333")     == 0.3333333333333333        -> False
float("9007199254740993")       == 9007199254740993.0        -> True
```

CPython answers `True` to all six.

## Cause

`pyfloat_parse` (`compiler/builtin/pylib.pas`) reconstructs the value with
FLOAT arithmetic — `intPart`, `frac`, `scale` are all `Double`, accumulated
digit by digit and scaled by powers of ten. Every one of those steps rounds, so
the result is *near* the correct double rather than being it. The failures
cluster where they should: large exponents, subnormal-adjacent values, and
17-significant-digit inputs.

`lib/rtl/sysutils.pas` has a correctly rounded one (`StrToFloatDef` — Clinger
fast path, exact `ExDecNearest` slow path) but a builtin unit may not use
`sysutils` (flat NilPy unit scope; see
[[decide-builtin-and-library-code-sharing]]).

## Why it matters beyond exactness

It breaks round-tripping in the direction users notice first: read a float from
JSON/CSV/config, write it back, and the bytes differ. It also makes any future
`repr` round-trip gate untestable from NilPy source, since the check itself
would run through the broken parser.

## Fix

Already decided and scoped — this is fixed by the same copy
[[bug-nilpy-float-repr-is-not-pythons-shortest-roundtrip]] performs: bring the
correctly-rounded parser closure (`ExDecCmp`, `ExDecBitsToDouble`,
`ExDecDoubleToBits`, `ExDecEstimate`, `ExDecNearest`, `StrToFloatDef`, ~304
lines) into the builtin layer and make `pyfloat_parse` a thin wrapper over it,
keeping its Python-specific front end (the `inf`/`nan`/`infinity` spellings and
the `ValueError` on a bad parse).

Doing the two together is the point: the repr work NEEDS a correct parser for
its round-trip check, and this ticket is what that parser also buys. Neither
should be landed with the other's half skipped.

## Gate

A `.npy` diffed against CPython over the six rows above plus: `float` of a
17-digit string, of a subnormal, of `1e-308`/`1e308` at both ends, and the
`inf`/`-inf`/`nan` spellings and the bad-parse `ValueError` as controls that the
Python front end still works. Ideally `float(str(x)) == x` over a table once
`repr` exists as a builtin
([[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]]).

## Resolved 2026-08-03 — together with the repr ticket, as the decision intended

`pyfloat_parse` no longer reconstructs the value at all. It keeps Python's
validation — where a sign, a point, an exponent and an underscore may appear,
which spellings raise `ValueError`, and the `inf`/`infinity`/`nan` forms — and
hands the accepted text to `PyStrToFloatDef`, the correctly-rounded parser
copied from `lib/rtl/sysutils.pas` for
[[bug-nilpy-float-repr-is-not-pythons-shortest-roundtrip]].

The three cases on this ticket now agree with pxx's own literals for the same
numbers, and are covered in `test/test_nilpy_float_repr.npy` both as printed
values and as `==` comparisons:

    float("1e308") == 1e308
    float("0.3333333333333333") == 0.3333333333333333
    float("2.2250738585072011e-308") == 2.2250738585072011e-308
    float("5e-324") == 5e-324

Net effect on the count of disagreeing float parsers in the tree: three become
two. The remaining pair is `sysutils.StrToFloatDef` and its pylib copy, which
are the same algorithm and are pinned against each other by tests — plus
`compiler/lexer.inc`'s `StrToDoubleBits`, which the sweep on the sibling ticket
proved is the one that is actually wrong
([[bug-a-float-literal-lexer-is-not-correctly-rounded]]).

## Log
- 2026-08-03 — resolved.
- 2026-08-03 — resolved, commit HEAD.
