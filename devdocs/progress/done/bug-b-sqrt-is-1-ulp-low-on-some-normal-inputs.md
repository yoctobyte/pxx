---
track: B
prio: 20
type: bug
blocked-by: []
summary: "Sqrt is 1 ULP low on some ordinary normal inputs — reproducibly at 2.215827865120445e276 and at DBL_MAX. The Dekker correction, not the bit-hack seed (the seed's failures were fixed in bug-b-sqrt-of-infinity-answers-nan). RARE: 20,000 random normals found zero, so random sampling will not find it and a targeted search is needed. Accuracy only; no special value or magnitude is involved."
status: done
owner: track-b-bughunt
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

## Resolution (2026-08-15)

Two defects, not one, and the second was found only because the first was
fixed properly.

### 1. The correction was an ESTIMATE where it could be a MEASUREMENT

`res := g + r/(2g)` is a rounded quotient added to a rounded g, so it can land
on the wrong side of the halfway point — which is exactly what the reported
values showed. It now DECIDES instead: take the exact residual of the answer,
and if it is non-zero compare it with the residual of the neighbouring double
in the direction the residual points. The smaller |x - root^2| is the nearer
root, and that is the correctly-rounded answer. `lib/crtl/src/math.c` already
had this step; this file did not. Same port-the-better-mechanism move as the
sibling ticket.

### 2. The exact residual stopped being exact at BOTH ends of the range

The ticket predicted "not a DBL_MAX edge", and that was right about the cause
being general — but the range ends do need one thing, and it is not a special
case, it is a scaling:

- **Near DBL_MAX** the Dekker split squares `gh`, which is g rounded UP to 26
  bits, so `gh*gh` overflows while `g*g` is still finite. The old guard tested
  `g*g` and so let those values through; the residual came back -Inf and Sqrt
  answered **-Inf** for the doubles just below DBL_MAX. That was a real
  (unreported) bug sitting next to the reported one.
- **Near the smallest normals** the mirror image: the split's smallest term,
  `gl*gl`, falls below the subnormal threshold and flushes to zero, so the
  residual is silently inexact. Four values in a 65,000-value sweep, all with
  x ~ 1e-307.

Both are fixed by ONE exact power-of-two rescaling, in either direction, which
removes the old "skip the correction" special case instead of adding a second
one.

### Result

**0 mismatches in 121,217 values** against libm (whose sqrt is correctly
rounded by IEEE mandate, so it is a valid oracle here): random across the whole
exponent range, dense sweeps at both ends and through the subnormals, 400
neighbours either side of each reported value, and ~36,000 values sitting
within a few ulp of a perfect square — the boundary hunt the ticket asked for.
The parent ticket's 5505-value differential is included in that and is clean.

### And then it was made FAST, because correctness had made it slow

The neighbour decision costs two extra exact residuals, and a 3M-call
benchmark measured the honest price: **269 ms -> 575 ms**. Shipping a 2x
slowdown on a primitive this hot, quietly, would have been the wrong trade.

On x86-64 `sqrtsd` IS the correctly-rounded square root — IEEE requires sqrt to
be exact and, unlike the transcendentals, the hardware delivers it, subnormals
and +-0 and the negative-NaN included. `Sqrt` is now that one instruction
there: **18 ms**, 15x faster than the code this ticket started with, and
correct by construction.

The portable implementation stays as `SqrtSoft`, exported and asserted in
`lib_math_correctly_rounded` on the same values. Without that, the code every
non-x86-64 target runs would never execute on the machine the gate runs on —
it would be reachable only through the cross sweep, which is not where a broken
residual should first surface. Verified under qemu on i386, aarch64 and arm32.

**Follow-up worth filing separately:** aarch64 `fsqrt` and arm32 `vsqrt` are
the same one-instruction win, and both hosts can be exercised here under qemu.
Not done under this ticket, which was about correctness.

## Log
- 2026-08-15 — resolved, commit 1a35da630.
