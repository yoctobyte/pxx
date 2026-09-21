---
track: B
prio: 45
status: open
type: perf
tags: [F, lekkerzeilen]
blocked-by: []
summary: "MECHANISM: Sin/Cos/Tan put the double-double (~106-bit) path behind {$ifdef PXX_FLOAT_EXACT} and default to SinCosFast; ArcTan, ArcTan2, ArcSin and ArcCos have NO fast arm and are unconditionally double-double. It SPRINGS for any program calling an inverse trig function in a loop, and it is not a precision trade-off but a 3-order-of-magnitude cost. MEASURED 2026-09-21, default build, x86-64, 2M calls each, min of 3 reps, ns/call: Sqrt 17.5, Cos 188, Sin 192, ArcTan2 14396, ArcTan 14780, ArcSin 17860, ArcCos 19129 -- ArcCos is 1095x Sqrt and 110x Cos, against a libm atan at 20-50 ns. Profiled (120 samples): no single pathology, the cost is ~50-60 non-inlined record-returning dd calls per atan, spread Dd2Prod 25.2 / DdAtan 18.7 / DdFast2Sum 15.9 / Dd2Sum 10.3. NOT DONE TODAY AND THE REASON IS THE MEASUREMENT, NOT CAPACITY: 7a counted call sites under CPython (same program logic, so counts transfer) and atan2 is the only one that pays -- rijn 1258.4/frame, roofs 46.0/frame, asin 0.2/frame, acos 24 calls in 150s, ATAN NEVER CALLED AT ALL. That is 18.1 ms/frame on rijn (3.6% of a 500ms frame) and 0.66 ms on the SHIPPING scene roofs (0.13%). Real, worth fixing, not transformative, and not frame-rate work. WHAT WOULD RAISE THIS: a program that calls an inverse trig function in bulk -- scientific or geometry code -- where 16 us/call is 500x a reasonable figure. THE FIX IS IN-PATTERN AND NOT A NEW MECHANISM: mirror the existing {$ifdef PXX_FLOAT_EXACT}/{$else} split onto the four inverse functions, keeping the exact arm under the flag so test/lib_math_correctly_rounded.pas is unaffected; test/lib_math_fast_tolerance.pas already asserts what the default mode must satisfy. The work that is NOT free is a correct plain-double atan kernel (reduction plus minimax polynomial) -- that is the whole cost of this ticket and the reason it is not a one-liner."
---

# The inverse trig functions have no fast arm and cost ~16 microseconds a call

`Sin`, `Cos` and `Tan` in `lib/rtl/math.pas` each carry two arms:

```pascal
{$ifdef PXX_FLOAT_EXACT}
  SinCosDd(Abs(x), sn, cs);      { ~106 bits }
{$else}
  SinCosFast(Abs(x), sc);        { the default }
{$endif}
```

`ArcTan` (1656), `ArcSin` (1693), `ArcCos` (1718) and `ArcTan2` (1759) have
**zero** `PXX_FLOAT_EXACT` guards. They are always double-double.

`PXX_FLOAT_EXACT` is defined in exactly one place in the tree — a `Makefile`
line for `test/lib_math_correctly_rounded.pas` — so `SinCosDd` is **unreachable
in any normal build**, while `DdAtan` is on the default path for every
`ArcTan2` call.

## Why it costs what it does

`DdAtan` runs up to six half-angle steps, each with a `DdSqrt` and a `DdDiv`,
then a **13-term series where every term is four double-double operations**,
then the doublings back. Roughly 50–60 non-inlined record-returning calls.

Profile of 400k `ArcTan` calls, 120 samples — **no single pathology, it is
volume**:

    Dd2Prod 25.2%   DdAtan 18.7%   DdFast2Sum 15.9%   Dd2Sum 10.3%
    DdMulD 7.5%   DdDivD 6.5%   DdMul 5.6%   DdAdd 4.7%

## A separate datum for Track O, measured here and not chased

Same binary, same 400k calls, three interleaved reps, min:

    -O0 5.77s    -O2 5.58s    -O3 3.93s

**`-O2` buys 3.3% on this code and `-O3` buys 31.9%.** Whatever `-O3` is doing
for dd-heavy record-returning code, `-O2` is not. Recorded because it was
measured, not because it has been investigated — it may be one pass, and it may
be specific to this shape.

## What the fix must not do

**Do not delete the exact arm.** `test/lib_math_correctly_rounded.pas` builds
with `-dPXX_FLOAT_EXACT` and asserts the last bit; the port to double-double
exists because the previous plain-double `ArcTan` disagreed with libm on
**2065 of 3005 random arguments, up to 4 ulp**. The fast arm must be a second
path, not a replacement, and `test/lib_math_fast_tolerance.pas` is where its
tolerance is asserted.
