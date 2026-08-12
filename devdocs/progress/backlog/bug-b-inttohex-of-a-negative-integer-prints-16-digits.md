---
track: B
prio: 40
type: bug
blocked-by: []
summary: "`IntToHex(-1, 8)` prints FFFFFFFFFFFFFFFF where FPC prints FFFFFFFF: lib/rtl/sysutils declares only the Int64 overload, so a 32-bit Integer argument is sign-extended to 64 bits and renders eight extra F's. Positive values agree, so it only shows on negatives — where hex is most often used"
---

# `IntToHex` of a negative Integer prints 16 digits, not 8

- **Type:** bug (wrong output) — **Track B** (`lib/rtl/sysutils.pas`)
- **Found:** 2026-08-12, differential bug hunting against FPC 3.2.2.

```pascal
var i: Integer;
begin
  i := -1;
  WriteLn(IntToHex(-1, 8));    { FPC: FFFFFFFF   pxx: FFFFFFFFFFFFFFFF }
  WriteLn(IntToHex(i, 8));     { FPC: FFFFFFFF   pxx: FFFFFFFFFFFFFFFF }
  WriteLn(IntToHex(i, 2));     { FPC: FFFFFFFF   pxx: FFFFFFFFFFFFFFFF }
end.
```

An `Int64` argument agrees (`FFFFFFFFFFFFFFFF` in both), and every positive
value agrees whatever its width, so the whole divergence is a negative value
whose declared type is 32-bit.

## Cause

`lib/rtl/sysutils.pas` declares one overload:

```pascal
function IntToHex(value: Int64; digits: Integer): AnsiString;
```

so an `Integer` argument is sign-extended into it and the top half's F's are
real digits by the time the routine sees the value. FPC declares the family
(`Byte`/`Word`/`Cardinal`/`Integer`/`Int64`…), and `digits` is a MINIMUM width
in both — which is why `IntToHex(i, 2)` still prints all of them rather than
truncating.

## The fix

Add the 32-bit overload (masking to `$FFFFFFFF` before rendering) beside the
Int64 one — and while there, the `Byte`/`Word`/`Cardinal` spellings FPC has, so
`IntToHex(b, 2)` on a byte cannot pick up sign extension either. Track A's
overload resolution already prefers an exact-width integer parameter over a
wider one ([[project_overload_resolution_single_side_channel_entry]]), so
adding the row is all that is needed.

## Gate

`make lib-test` plus a `.pas` diffed against FPC: -1 / -255 / MinInt as
`Integer`, the same values as `Int64`, positives of each width, `digits`
smaller and larger than the natural width, and a `Byte`/`Cardinal` argument.
