# `types` unit (System.Types core) — geometry records + TDuplicates

- **Type:** feature (library — RTL, Track B)
- **Status:** DONE 2026-07-04
- **Owner:** Track B

## What / why

Real FPC/FCL units `uses Types` (FPC's `System.Types`). `fgl` needs
`TDuplicates`; GUI/geometry code wants `TPoint`/`TRect`/`TSize`. pxx had no
`types` unit, so those units hit `uses: unit source not found: types`.

## Done

Added `lib/rtl/types.pas` (Zlib, matching the rest of `lib/rtl`) with the common
System.Types core, minimal + extendable:

- `TValueRelationship = -1..1` + `LessThanValue`/`EqualsValue`/`GreaterThanValue`.
- `TDuplicates = (dupIgnore, dupAccept, dupError)`.
- `TPoint`/`PPoint`, `TSmallPoint`, `TSize`, `TRect`/`PRect` records.
- Constructors `Point`/`SmallPoint`/`Size`/`Rect`/`Bounds` + `RectWidth`/
  `RectHeight` helpers.

Resolves via pxx's normal `uses` search (`lib/rtl`); libc-free. Verified with
both the fresh and the pinned-stable compiler; `fgl` now gets past its
`uses types` wall (advances to the class-methods-in-generic member gap,
[[feature-class-methods-in-generic-class]]).

## Extend later (as consumers need)

`TRectF`/`TPointF` float variants, `TByteArray`/`TWordArray` helpers, more Rect
ops (Intersect/Union/Contains), `TListSortComparer` typedef. Left out until a
consumer needs them.
