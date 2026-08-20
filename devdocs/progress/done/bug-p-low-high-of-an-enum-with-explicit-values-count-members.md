---
track: P
prio: 70
type: bug
blocked-by: []
summary: "Low/High of an enum type answered 0..count-1 — the declaration-index range — instead of the range of the members' VALUES. `TGap = (gX = 3, gY = 4, gZ = 9)` gave Low=0 and High=2, two ordinals that are not values of the type, so `for g := Low(TGap) to High(TGap)` walked 0,1,2 and stopped six short of gZ. Silent."
status: done
owner: frank1-ACP
---

# `High(TGap)` counts the members instead of reading their values

- **Track P** (Pascal frontend: the two Low/High folders in `parser.inc`, plus
  one new accessor in `symtab.inc`).
- Found 2026-08-20 by an FPC differential probe over enums, sets and subranges.

## Repro

```pascal
type
  TGap = (gX = 3, gY = 4, gZ = 9);
  TCol = (cRed, cGreen = 5, cBlue, cGold = 20);
```

|                    | FPC 3.2.2 | pxx (before) |
| ------------------ | --------- | ------------ |
| `Ord(Low(TGap))`   | 3         | **0**        |
| `Ord(High(TGap))`  | 9         | **2**        |
| `Ord(High(TCol))`  | 20        | **3**        |
| `for g := Low(TGap) to High(TGap)` | 3,4,5,6,7,8,9 | **0,1,2** |

`Ord(gX)`, `Ord(cGold)` etc. were already right — only the type's *bounds* were
wrong. So the enum's own values check out and only the loop that walks them is
broken, which is why this survived: nothing in the corpus iterates an enum whose
members carry explicit ordinals.

## Root cause

`0 .. EnumTypeValCount[etid] - 1` was written out longhand at **four** sites as
the stand-in for "the ordinal range of this enum type":

| site | what it bounds |
| --- | --- |
| `TryConstHighLowValue` (`parser.inc`) | `Low`/`High` in a constant expression |
| `TryFoldHighLowType` (`parser.inc`)   | `Low`/`High` in an expression |
| `BuildForInSetLoop` (`parser.inc`)    | the `for x in <set of enum>` membership scan |
| the array-index-type bound (`parser.inc`) | `array[TEnum] of …` |

That shorthand is exact for a plain `(a, b, c)` and wrong for every enum with an
explicit `= N`. `EnumTypeHasHoles` already existed and already recorded that the
declaration broke contiguity — it was consulted only to refuse `for x in TEnum`,
never to correct a bound.

## Fix

One accessor, `EnumTypeOrdRange(etid, var lo, hi)` in `symtab.inc`, scanning
`EnumValOrd` over the type's member slice; all four sites call it. The change is
a no-op for a contiguous enum (min = 0, max = count-1 by construction) and a fix
for every other one — so the set scan and the array-index bound are corrected by
the same edit that fixes `Low`/`High`, rather than each growing its own patch.

Fallout worth naming: `array[TGap] of Integer` is now **7** slots indexed from 3,
not 3 slots indexed from 0. FPC refuses that declaration outright; pxx accepts it
and now sizes it the only way that can work, since `ag[gZ]` was previously an
out-of-bounds write six elements past the array.

## Test

`test/test_enum_explicit_ordinal_low_high.pas` — 24 assertions: the contiguous
enum (unchanged, so a regression is caught), the all-explicit one, the
mid-declaration gap, `set of` a holed enum (`in`, `Include`, `Exclude`, for-in),
and `array[TGap]`. Every expectation is FPC 3.2.2's except `array[TGap]`, which
FPC will not compile.

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
