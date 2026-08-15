---
track: B
prio: 20
type: bug
blocked-by: []
summary: "Sqrt is 1 ULP low on some ordinary normal inputs — reproducibly at 2.215827865120445e276 and at DBL_MAX. The Dekker correction, not the bit-hack seed (the seed's failures were fixed in bug-b-sqrt-of-infinity-answers-nan). RARE: 20,000 random normals found zero, so random sampling will not find it and a targeted search is needed. Accuracy only; no special value or magnitude is involved."
---

# `Sqrt` is 1 ULP low on some normal inputs

- **Type:** bug (accuracy) — **Track B** (`lib/rtl/math.pas`).
- Split out of [[bug-b-sqrt-of-infinity-answers-nan]] on 2026-08-15, which fixed
  everything the *seed* got wrong (+Inf, NaN, -0, all denormals). This is what
  is left, and it is in the correction step instead.
- Sibling of [[bug-b-arcsin-arccos-lose-2-ulps-vs-libm]] — same class, same
  unit, both accuracy rather than blow-ups.

## Reproduce

```
x = 2.215827865120445e276     pxx 1.4885657073574029e138   libm 1.4885657073574027e138
x = 2.2158278651204453e276    pxx 1.4885657073574029e138   libm 1.4885657073574030e138
x = 1.7976931348623157e308    pxx 1.3407807929942597e154   libm 1.3407807929942596e154
```

Nothing special about these: ordinary finite normals, no subnormal, no infinity.
`Sqrt`'s own header claims the correction yields *"the correctly-rounded
result"*, and for these inputs it does not.

## It is the correction, not the seed — and NOT a DBL_MAX edge

Worth stating, because the obvious story is wrong and was tested:

- `DBL_MAX` looks like an overflow edge (`g*g` → `+Inf`, the documented
  skip-the-correction path). **It is not that path.** Measured: `g*g` stays
  finite for `DBL_MAX`, so the correction runs and still lands 1 ULP high.
- Rescaling by an exact power of two before correcting — the trick that fixed
  the denormals — was implemented and **changed nothing**: `Sqrt(DBL_MAX/2^106)`
  is *itself* 1 ULP off, which is how `2.215827865120445e276` was found. That
  guard was reverted rather than left in as a case that buys nothing.

So the defect follows the value into the middle of the range; it is a property
of the Dekker residual step.

## The measurement problem — read this before sampling

**It is rare.** 20,000 uniformly-random normal doubles produced **zero**
mismatches; a separate 5,505-value run produced exactly one, and only because
`DBL_MAX` was in the hand-written edge list. A random differential will report
green and mean nothing.

So: search deliberately. Sweep mantissas near the rounding boundary (values
whose exact root sits within a hair of a halfway point), walk neighbours of the
known-bad values bit by bit, and test `x` where `g*g` is nearly exact. The
existing harness (feed a value list on stdin to a `.pas` printing
`FloatToStrExact(Sqrt(x), 17)`, diff against `math.sqrt` in CPython) is the
right shape; only the input generator has to change.

## Gate

The three values above match libm, a targeted boundary sweep finds no others,
and the 5505-value differential from the parent ticket goes to **zero**
mismatches. `make lib-test` green.
