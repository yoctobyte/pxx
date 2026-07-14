---
prio: 50
---

# `typinfo` facade unit: FPC's RTTI API shapes over OUR blobs

- **Type:** feature (library — Track B)
- **Status:** backlog — filed 2026-07-14.
- **Depends on:** [[feature-typeinfo-all-types]] (the blobs to read).
- **Blocks:** [[feature-pascal-corpus-generics]], the RTTI->streaming->LFM line,
  [[feature-embed-dwscript-rtti]], fpjsonrtti.

## The insight this rests on
Real code does NOT read FPC's RTTI bytes. It reaches RTTI through the `typinfo`
UNIT's record declarations and accessors — `GetTypeData`, `GetPropInfo`,
`GetEnumName`, `PropType`, `TTypeKind` — and **those declarations live inside
typinfo**. Since we supply typinfo, we choose what the records look like and how
they are filled. Therefore: **no FPC byte-layout parity, and no fork of any
consumer library.** (Layout would only leak for code doing pointer arithmetic
past the published API — rare; handle it if a corpus target actually does.)

## The work
Grow `lib/rtl/typinfo.pas` from its current enum-only surface into the API FPC
consumers actually call:
- `TTypeKind` enumeration + `PTypeInfo` / `TTypeData` / `PPropInfo` shapes,
  declared to be convenient over OUR blobs (not byte-copies of FPC's).
- `GetTypeData`, `GetPropInfo`, `GetPropList`, `PropType`, and the property
  get/set helpers the streaming code uses.
- Keep the existing `GetEnumName` / `GetEnumValue` / `GetEnumNameCount` (already
  the same pattern, proven by fpjson).

Honesty rule, as everywhere in this RTL: where a shape cannot be answered, say
so at the declaration rather than returning a plausible lie.

## Gate
`make lib-test` + the consumers that motivated it compile (start with
generics.defaults, then fpjsonrtti).
