---
track: B
prio: 30
type: feature
blocked-by: []
summary: "lib/rtl/sysutils has StrToTime but no StrToDate, StrToDateTime, or any of the TryStrToDate/Time/DateTime variants — the parse direction of the date surface is half absent while the format direction (FormatDateTime, EncodeDate, DecodeDate) is complete. Found when a differential probe would not compile against pxx."
---

# `sysutils`: `StrToDate` / `StrToDateTime` and the `TryStrTo*` date variants

- **Type:** feature (library gap) — **Track B** (`lib/rtl/sysutils.pas`).
- Found 2026-08-14 during an FPC differential sweep of the conversion family:
  the probe would not compile until `StrToDate` and `StrToDateTime` were removed
  from it.

## What is there and what is not

| direction | present | missing |
| --- | --- | --- |
| format | `FormatDateTime`, `DateToStr`?, `EncodeDate`, `EncodeTime`, `DecodeDate`, `DecodeTime` | — |
| parse | `StrToTime` | **`StrToDate`, `StrToDateTime`** |
| non-raising | `TryStrToInt`, `TryStrToFloat`, … | **`TryStrToDate`, `TryStrToTime`, `TryStrToDateTime`** |

So the surface is asymmetric: a program can format a date but not read one back.

## Notes for whoever takes it

- **`ShortDateFormat` decides the field ORDER**, and that is the whole
  difficulty — `StrToDate('2026-08-14')` is not universally valid, and FPC
  raises for it under a `dd-mm-yyyy` order. Take the order from the settings,
  do not hardcode ISO.
- `DateSeparator` is the separator, exactly as
  [[bug-b-formatdatetime-emits-slash-and-colon-literally]] established for the
  format direction. Reuse that, do not grow a second rule.
- Raise **`EConvertError`**, and match FPC's message wording per field type —
  measured, `StrToTime`'s is `"%s" is not a valid time`, which does NOT follow
  the integer arms' `"%s" is an invalid integer` pattern
  ([[bug-b-strtotime-raises-the-wrong-class-and-rejects-milliseconds]]).
- The `TryStrTo*` variants must not raise, and should share one parser with the
  raising ones — the split is where this family keeps going wrong.
- Steal `StrToTime`'s freshly-verified millisecond rule for the time half of
  `StrToDateTime`: a millisecond FIELD (max 3 digits, `.25` is 25 ms), not a
  decimal fraction.

## Gate

A `.pas` diffed against FPC 3.2.2 covering each function, valid and malformed
input, `ShortDateFormat`/`DateSeparator` variations, the raising and non-raising
variants, and leap-day and year-boundary dates. `make lib-test` green.
