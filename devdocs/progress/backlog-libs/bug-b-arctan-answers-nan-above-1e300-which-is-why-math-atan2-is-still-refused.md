---
slug: bug-b-arctan-answers-nan-above-1e300-which-is-why-math-atan2-is-still-refused
track: B
prio: 55
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [rtl, math, arctan, atan2, nilpy, stale-hazard]
blocked-by: []
summary: "`ArcTan(x)` answers NaN for |x| >= about 1e301 where the right answer is +-pi/2. Boundary measured 2026-09-10 at compiler `5a2cef142106`: 1e300 correct, 1e301 NaN, everything above NaN. It propagates to `ArcTan2` whenever |y|/|x| lands there. AND IT RETIRES A STALE HAZARD BLOCK: pyparser.inc's math table says `math.atan2 is still absent, and stays absent: ArcTan2 is 1 ulp off CPython for atan2(0.5, 1) ... blocked on a correctly-rounded libm`. Re-measured bit for bit over 1005 argument pairs, ArcTan2 is IDENTICAL to CPython on 996 and every one of the 9 that differ is this NaN, not a rounding difference -- atan2(0.5, 1) itself is bit-identical (3FDDAC670561BB4F both). So `math.atan2` is NOT blocked on correctly-rounded libm; it is blocked on one overflow guard in ArcTan, and 7 lekkerzeilen modules are waiting behind it. The recorded 1-ulp figure looks like a repr-vs-fixed-width readout of the same value."
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
