---
track: B
prio: 35
type: bug
blocked-by: []
summary: "variants.pas has no VarToStr, so `WriteLn(VarToStr(v))` — the ordinary way to print a Variant in FPC/Delphi code — fails with `undefined variable (VarToStr)`. The unit already has the whole implementation as a private helper (`AsText`), so this is an export, not a feature. Found while writing the differential for bug-a-an-out-parameter-of-a-managed-type-is-not-cleared, which could not be written against the FPC oracle until VarToStr was removed from it."
---

# `VarToStr` is missing from `variants`

- **Type:** bug (a routine ordinary FPC source calls) — Track B (`lib/rtl/variants.pas`)
- **Status:** backlog
- **Opened:** 2026-08-22

## Measured

```pascal
uses Variants;
var v: Variant;
begin
  v := 'vv';
  WriteLn(VarToStr(v));
end.
```

| | result |
| --- | --- |
| FPC 3.2.2 | `vv` |
| pxx | `pascal26:5: error: undefined variable (VarToStr)` |

## Why it is cheap

`variants.pas` already computes exactly this. `AsText(const V: Variant; t:
TVarType): AnsiString` (line ~185) is the private helper `VarCompareValue` uses
to compare two text variants; `VarToStr(V)` is `AsText(V, VarType(V))` with
FPC's one documented special case — **Null yields the empty string** rather than
raising, which is the entire reason callers reach for `VarToStr` instead of a
plain cast. So the work is an export plus the Null arm, not an implementation.

Worth checking the siblings in the same pass, since a caller who wants one
usually wants the set: `VarToStrDef`, `VarToWideStr`, `VarAsType`, `VarClear`.
Add what is a one-liner over the existing helpers; file the rest rather than
half-building them.

## Where it was found

Writing the FPC differential for
[[bug-a-an-out-parameter-of-a-managed-type-is-not-cleared]] — the natural way
to show that an `out Variant` was cleared is to print it, and that row had to be
rewritten to assign through an AnsiString first.

## Gate

Track B's: build with `$(PXX_STABLE)`, `make lib-test`. Plus the four-line
program above matching fpc 3.2.2, and a Null row (`VarToStr` of a Null variant
is `''`, not an exception).
