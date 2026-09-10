---
slug: bug-b-arctan-answers-nan-above-1e300-which-is-why-math-atan2-is-still-refused
track: B
prio: 55
type: bug
status: done
owner: ""
created: 2026-09-10
found-by: frankB
tags: [rtl, math, arctan, atan2, nilpy, stale-hazard]
blocked-by: []
summary: "RESOLVED 2026-09-10, and it was THREE defects rather than the one this ticket reported. `ArcTan(x)` answered NaN above DBL_MAX/(2^27+1) = 1.3393857490036326e300 -- the Dekker split inside Dd2Prod, not anything in the series -- and ArcTan2 additionally formed |y|/|x| before checking it (a ratio past DBL_MAX gave DdDivD an Inf to subtract from an Inf) and had no answer at all for an infinite operand. A fourth, the mirror at the other end, showed up once the NaNs cleared: a SUBNORMAL dividend makes DdDivD/DdDiv underflow their refinement product, so the residual is noise amplified by 1/b, and on all nine such rows the plain double quotient was already correct. 6000 random pairs on the raw bits against glibc: was 913 NaN rows + 9 wrong, now 0 of 6000 on atan2, atan(y) and atan(x), with zero rows moving from one finite value to a different one. AND IT RETIRED A STALE HAZARD BLOCK: the 1-ulp gap that kept math.atan2 out of pyparser.inc for a month never existed -- the two figures in the note are one double printed by repr and by a :0:20 fixed readout. Original report follows. Boundary as first measured: 1e300 correct, 1e301 NaN. It propagates to `ArcTan2` whenever |y|/|x| lands there. AND IT RETIRES A STALE HAZARD BLOCK: pyparser.inc's math table says `math.atan2 is still absent, and stays absent: ArcTan2 is 1 ulp off CPython for atan2(0.5, 1) ... blocked on a correctly-rounded libm`. Re-measured bit for bit over 1005 argument pairs, ArcTan2 is IDENTICAL to CPython on 996 and every one of the 9 that differ is this NaN, not a rounding difference -- atan2(0.5, 1) itself is bit-identical (3FDDAC670561BB4F both). So `math.atan2` is NOT blocked on correctly-rounded libm; it is blocked on one overflow guard in ArcTan, and 7 lekkerzeilen modules are waiting behind it. The recorded 1-ulp figure looks like a repr-vs-fixed-width readout of the same value."
---

# Measured 2026-09-10, compiler `5a2cef142106`

## The boundary

| x | ArcTan(x) |
| --- | --- |
| 1e295 … 1e300 | bit-identical to CPython |
| 1e301 and above | `FFF8000000000000` (NaN); CPython `3FF921FB54442D18` (pi/2) |
| -1e301 and below | `7FF8000000000000`; CPython `BFF921FB54442D18` |

## The sweep that says it is the ONLY divergence

1005 `atan2` argument pairs — 600 uniform over ±1e4, the four sign
combinations on and near both axes, every decade from 1e-320 to 1e308 as a
ratio, and 120 subnormal pairs — compared as raw IEEE bits against CPython:

```
identical: 996 of 1005
differ:      9   all of them this NaN
```

The differing rows are `atan2(±1, 1e-320 … 1e-304)` and
`atan2(±1, 1e304)` / `atan2(1e304, 1)` — i.e. exactly where `|y|/|x|` lands
above the ArcTan boundary. A separate 316-point `ArcTan` sweep isolates it to
`ArcTan` itself: 312 identical, 4 differ, all `|x| >= 1e301`.

## Why the recorded objection is retired

`compiler/pyparser.inc`'s math table carries:

> math.atan2 is still absent, and stays absent: ArcTan2 is 1 ulp off CPython
> for atan2(0.5, 1) (0.46364760900080615 vs ...09), so mapping it would be a
> silently wrong value in the last place. Blocked on a correctly-rounded libm.

`atan2(0.5, 1)` is **bit-identical**: `3FDDAC670561BB4F` in both. The two
figures in that note are the same double printed two ways — `repr` gives
`0.4636476090008061`, a 20-place fixed readout gives `0.46364760900080609352`.
This is CLAUDE.md's readout-collision rule running in the other direction: the
readout manufactured a DISAGREEMENT rather than an agreement, and the note has
kept `math.atan2` out of the table ever since.

**A hazard block decays like a lock, not like a fact** — nobody who obeys it
generates anything that could reveal it was wrong. This one was obeyed.

## The mechanism

`DdAtan` inverts for `t.Hi > 1.0` via `DdDiv(one, t)`, then runs a
half-angle reduction. Somewhere on that path a double-double intermediate
overflows for a very large `t` — `ArcTan2` reaches it through
`q := DdDivD(Dd2Sum(Abs(y), 0.0), Abs(x))`. The answer for any `|t|` past
about 2/eps is pi/2 to the last bit anyway, so the fix is a magnitude guard
ahead of the reduction, not a better series.

## What a fix must carry

The bit-level differential, not a printed comparison — a `:0:20` readout is
what hid this for as long as it has been hidden. `test/` has no ArcTan
differential today; the sweep above is the shape, with the boundary rows
(1e300 correct, 1e301 correct) as the positive control, since a guard placed at
the wrong threshold passes every ordinary row.

## What it unblocks

`math.atan2` is the largest single wall in the lekkerzeilen corpus: 6 modules
(hud, rig, sim, traffic, vessel, world) as of the 2026-09-10 census, out of 33.

## Resolved 2026-09-10 — the cause was one line further down than this ticket said, and there were three defects, not one

**My own mechanism section above was wrong and it is left standing rather than
edited.** It said "somewhere on that path a double-double intermediate
overflows ... the fix is a magnitude guard ahead of the reduction, not a better
series". The first half is right in outline and useless in practice; the
second half names a remedy that would have papered over the real defect and
left every other caller of the same kernel broken.

### 1. The Dekker split overflows long before the product does

`Dd2Prod` — the two-product every double-double multiply, divide and square
root in `lib/rtl/math.pas` is built on — split its operands by multiplying by
`2^27+1`. That product is `+Inf` for `|a| > DBL_MAX/(2^27+1) =`
**1.3393857490036326e300**, so `sa - (sa - a)` was `Inf - Inf = NaN` for an
argument whose actual product is finite and small.

The boundary this ticket recorded as "1e300 correct, 1e301 NaN" is exactly
that constant. `ArcTan` reaches it because `DdAtan` inverts a large `t` through
`DdDiv`, whose first step is this multiply.

Fixed by scaling by `2^-28` before the split and scaling **the product** back,
not the halves. Scaling the halves back is the obvious spelling and it still
answered NaN for `DBL_MAX` itself — `ah` is `a` rounded UP to 26 bits, so
`ah * 2^28` is `2^1024` while `a` is finite. `SqrtSoft`, a few hundred lines
up in the same file, documents that exact trap on `gh*gh` and its comment
already prescribed the answer: *"one exact power-of-two scaling ... removes the
special case instead of adding a second one."* Of two paths for one concept,
the one nobody extended is the one that stayed broken.

### 2. `ArcTan2` formed a quotient that overflows

Independent of the split: `|y|/|x|` past `DBL_MAX` gave `DdDivD` an `Inf` to
subtract from an `Inf`, and the NaN it returned carried no sign to recover from.
`ArcTan2(1e301, -1e-301)` answered NaN where glibc answers pi/2. Guarded ahead
of the division — pi/2 is correctly rounded for the whole region, since a ratio
beyond `DBL_MAX` puts the angle within 5.6e-309 of pi/2 and one ulp of pi/2 is
2.2e-16.

### 3. `ArcTan2` had no answer for an infinite operand at all

Not in this ticket and not in any other. C99 F.10.1.4 gives all twelve
combinations a value and only the two signs decide; every one of them was NaN.
**Ten of the nineteen infinite pairs in the sweep were right by accident**,
which is why a pass/fail count alone would have called this fixed.

### 4. And the mirror at the other end: a SUBNORMAL dividend

Found by the same sweep once the NaNs cleared. `DdDivD` and `DdDiv` refine
their quotient by multiplying it back, so the product they form is `a.Hi`
again — and when `a.Hi` is subnormal that product underflows, the Dekker
residual is noise rather than the exact error, and dividing the noise by `b`
amplifies it by `1/b`. Nine of 6000 pairs were out by up to ~450000 ulp, and
on every one **the plain double quotient was already the correctly rounded
answer**: the double-double refinement is what made them worse. More precision,
applied where the representation cannot hold it, is less precision.

Fixed by the same one-exact-scaling shape at the other end of the range. It is
a LOOP and not one `2^64` step because being normal is not the bar — the
residual sits another `2^53` below the product, so a dividend just above
`DBL_MIN` is still 1 ulp out after a single lift. Measured: one step took the
sweep from 9 disagreements to 1, the loop to 0.

## The measurement

6000 random `(y, x)` pairs, exponents uniform over [-320, 308], both signs,
subnormals and infinities included, compared against glibc through CPython on
the **raw IEEE bits**:

| | before | after |
| --- | --- | --- |
| rows carrying a NaN | 913 | 0 |
| `ArcTan2` differs from glibc | 913 NaN + 9 wrong | **0** |
| `ArcTan(y)` differs from glibc | — | **0** |
| `ArcTan(x)` differs from glibc | — | **0** |
| rows the fix changed from one FINITE value to a different one | — | 0 |

That last row is the one that says the change is additive: no answer that was
already right moved.

## The harness lied first, and that is worth more than the fix

The first run of this sweep reported **2569 of 6000 `ArcTan` values wrong**
against a file header that says `ArcTan` is exact. It was the instrument: the
Pascal side read its arguments as decimal strings through `Val`, which is not
a correctly-rounded parser — 1574 of the same 6000 strings reach a different
double than CPython's `float()` does. Filed as
[[bug-b-val-of-a-float-is-not-correctly-rounded-while-strtofloat-of-the-same-string-is]];
`StrToFloat` on the identical strings is 0 of 6000 wrong, so it is two
mechanisms for one concept again.

Feeding the sweep as raw hex bits, **with a round-trip precondition asserted
and BRANCHED on** (`Halt(3)` if `Bits(FromBits(h)) <> h`), took it to 0 of 6000.
A comparison whose inputs were never proven to be the inputs cannot fail
honestly.

## What landed

- `lib/rtl/math.pas` — `Dd2Prod` scale-safe split; `DdDivD`/`DdDiv` subnormal
  scaling loop; `ArcTan2` ratio-overflow and infinite-operand arms.
- `test/lib_math_correctly_rounded.pas` — 30 new bit-level rows. Positive
  control: they produce **30 FAILURES** against the unpatched RTL and
  `MATHROUND OK` against the patched one, and `ArcTan(1.33e300)` — the row
  just BELOW the split threshold — passes in both, which is what makes the
  1.34e300 row mean something.
- `compiler/pyparser.inc` — `math.atan2` -> `ArcTan2`, and the stale hazard
  block corrected in place rather than deleted.
- `test/test_nilpy_math_atan_and_atan2_bit_for_bit.npy` + its Makefile row,
  oracled against live CPython.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 0838c1be3.
