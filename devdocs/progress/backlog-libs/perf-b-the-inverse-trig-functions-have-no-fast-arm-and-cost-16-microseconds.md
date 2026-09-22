---
track: B
prio: 45
status: open
type: perf
tags: [F, lekkerzeilen]
blocked-by: []
summary: "RESOLVED for ArcTan and ArcTan2 (FastAtanD, the fdlibm kernel, behind the existing {$else} arm); ArcSin and ArcCos DELIBERATELY LEFT on the double-double path and that is the part a future reader must not undo casually. MECHANISM, unchanged: a fast arm exists for Sin/Cos/Tan behind {$ifdef PXX_FLOAT_EXACT} and the inverse family had none, so every ArcTan2 paid ~106 bits for a 53-bit answer. MEASURED 2026-09-22 on pinned v416 fddc21e7e6615f80, both arms built with that binary, min-of-5 net of a measured loop control, box at load 27-30: dd 29463 ns/call vs fast 222 ns/call, 133x net (85x gross). CARRY BOTH ROWS: this ticket previously recorded 14396 ns/call for the same function on an unstated box and input distribution; the two are not reconciled and neither refutes the other. ACCURACY: max 1 ulp against glibc over ~15600 rows spanning all four reduction brackets, 0 rows past the 2-ulp contract test/lib_math_fast_tolerance.pas asserts; the exact arm is untouched and test/lib_math_correctly_rounded.pas passes unchanged under -dPXX_FLOAT_EXACT. WHY ArcSin/ArcCos ARE NOT DONE AND WHAT WOULD CHANGE THAT: on the SHIPPING scene roofs asin is 3.5 calls/frame and acos ~0; the 0.2/frame and 24-calls-in-150s figures this summary carried until 2026-09-22 are the OTHER column, rijn, and I attached them to roofs by collapsing 7a's two-column table into prose (corrected against lekkerzeilen devdocs/perf/PROFILE-2026-09-21.md:223). THE TWO FUNCTIONS MOVE IN OPPOSITE DIRECTIONS BETWEEN THE SCENES AND 3.5-ON-ROOFS IS NOT A TRANSCRIPTION ERROR: atan2 is 27x heavier on rijn (1258.4 vs 46.0) while asin is 17x heavier on roofs (3.5 vs 0.2), so a reader who has internalised 'rijn is the dense scene' will want to swap 3.5 back and must not. The document fixes column order at the atan2 row and every later row inherits it silently, so a reader who joins at row two has no cue at all. The decision is UNCHANGED and the corrected numbers still support it: 3.5 calls/frame at the measured dd cost (~29.5 us) is ~0.1 ms, ~0.02% of a 624 ms frame. And the plain-double asin/acos identity historically measured up to 8 ulp (acos up to 1099 ulp when taken as pi/2 - asin) -- all of the accuracy risk and none of the win. It SPRINGS if a program calls asin or acos in bulk; the fix would then need its own kernel, not the atan identity in plain double. KNOWN RED, STANDING AND ATTRIBUTED TO ME: the fast arm moves 20 of 272 rows in test/test_nilpy_math_atan_and_atan2_bit_for_bit.npy by EXACTLY 1 ulp (histogram {1:20}, zero rows worse), reproduced on plexus so not environmental. The test file's own stated purpose still passes -- no NaN anywhere, every large-argument row gives pi/2, every raw-BYTES struct row agrees -- so the Dekker-split overflow it was built to pin is still pinned. The contract question is with frankuser and the owner; I have NOT touched the test and will not, because narrowing it is a loosening AND it is the change that makes my own work pass. THIS IS NOT A FRAME-RATE LEVER AND MUST NOT BE RANKED AS ONE: at 46 atan2/frame on the shipping scene roofs it is 1.36 ms, which is 0.14% of a ~1 s frame."
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

## The bit-for-bit assertion is singular, and that is what makes the fork narrow

Measured 2026-09-22, independently by frankuser and re-verified here against the
tree. **Population: the 8 `test_nilpy_math_*.npy` files.**

| | count | held to |
| --- | ---: | --- |
| with a stored `.expected` | 5 | a frozen copy of OUR OWN output |
| without one (live CPython diff) | 3 | CPython's live bits |

The three without are `atan_and_atan2_bit_for_bit`, `fabs_os_basename` and
`floor_ceil_int`. **The latter two touch only exact operations** — the complete
set of `math.` calls in both files is `ceil`, `copysign`, `fabs`, `floor`,
`trunc`, where bit-for-bit is free and carries no contract.

**So `atan`/`atan2` is the only transcendental anywhere in the suite held to
CPython's live bits.** Every other one — `acos asin log log10 log2 pow sqrt
degrees radians frexp fsum modf isqrt` — is held to a frozen copy of our own
output. And `math.sin` / `math.cos` / `math.tan` are referenced by **no** nilpy
math test at all, despite having had fast arms for a long time.

**Corroborating measurement, mine:** `sin`/`cos` already differ from CPython on
**51 of 273 rows (18.7%)** in the tree as it stands, with nothing of mine in it.
A sibling `test_nilpy_math_sin_bit_for_bit.npy` written today would be RED on
arrival and would have been for months.

**So the file has been asserting "this function has not been optimised yet"
rather than "this function is exact"** (7a's phrasing). Its header explains the
regenerating oracle as a defence against staleness, which is a good reason that
carried a contract as a side effect nobody chose.

**The fork, for whoever settles it:** *is bit-for-bit with CPython the contract
for transcendentals, given it is already false for `sin`/`cos` and has been for
some time?* If it was never the intent, this red is a test that was passing for
the wrong reason. If it IS the intent, `sin`/`cos` are 51 rows out of contract
today and that is the larger defect. **Deliberately no fix pre-registered here.**
