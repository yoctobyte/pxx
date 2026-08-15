---
track: B
prio: 30
type: feature
blocked-by: []
summary: "lib/rtl/sysutils has StrToTime but no StrToDate, StrToDateTime, or any of the TryStrToDate/Time/DateTime variants — the parse direction of the date surface is half absent while the format direction (FormatDateTime, EncodeDate, DecodeDate) is complete. Found when a differential probe would not compile against pxx."
status: done
owner: track-b-bughunt
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

## Resolution (2026-08-15)

`StrToDate`, `StrToDateTime`, `TryStrToDate`, `TryStrToTime`, `TryStrToDateTime`
landed in `lib/rtl/sysutils.pas`, plus the two settings the parse direction
needs and the RTL did not have: **`ShortDateFormat`** (default `'d/m/y'`, FPC's)
and **`TwoDigitYearCenturyWindow`** (default 50).

Two FPC 3.2.2 probes, 53 rows total: probe 1 matches on **28 of 28**, probe 2 on
**24 of 25**. `test/lib_dateparse.pas` is new (36 rows, wired into `lib-test`),
and every row in it was read off FPC rather than reasoned about.

### What was measured, and would have been got wrong

- **Field ORDER comes from `ShortDateFormat` and ISO is not special.** With the
  `d/m/y` default, `StrToDate('2026-08-14')` **raises** — 2026 is read as the
  day — exactly as FPC does. Hardcoding ISO is the obvious implementation and it
  passes any test written by the person who hardcoded it.
- **Field COUNT changes the meaning:** one field is a day (current month and
  year), two are day+month (current year), three follow the format, four raise.
  A trailing separator is tolerated; `'14-08-2026-'` parses.
- **The two-digit-year window SLIDES.** `'49'` is 2049 and `'99'` is 1999, from
  `((CurrentYear - Window) div 100) * 100` with a +100 correction — not a fixed
  19xx/20xx cutoff, so a test written today keeps passing in 2031.
- **Two failure classes with different messages,** and callers match on them: a
  shape that does not scan gives `"%s" is not a valid date format`, while fields
  that scan but name no real day (month 13, 29 Feb 2026, day 2026) give the
  unquoted `Invalid date`.
- **`StrToDateTime` validates the TIME half first** — `'12:34:56 14-08-2026'`
  is blamed on the right-hand token being an invalid *time*, not on the left
  being an invalid date. The order is observable through the message.
- **A failed `TryStrTo*` CLEARS its value** (FPC declares it `out`, and 0 is
  what a caller who ignores the Boolean sees). Matched deliberately.
- Milliseconds reuse `StrToTime`'s verified rule: a millisecond FIELD, `.25` is
  25 ms.

`StrToTime` was refactored into `TryStrToTime` + a two-line raising wrapper, and
`StrToDate`/`TryStrToDate` share `ParseDate` the same way — the raising and
non-raising arms cannot drift, which is the specific way this family has gone
wrong before.

### Known divergence, message text only

`StrToDate('14 08 2026')` (spaces where the separator belongs) raises
`"14 08 2026" is not a valid date format` where FPC says `Invalid date`. Both
raise `EConvertError`, both reject the input; only the class of message differs.
It is left as-is because FPC's own split is not derivable from behaviour —
`'2026/08/14'` (also a wrong separator) gives FPC the *format* message, so no
single rule reproduces both rows, and inventing one would be a guess dressed as
parity.

### Not done here

`ShortTimeFormat` and the `DateToStr`/`TimeToStr`/`DateTimeToStr` renderers are
still absent. They belong to the FORMAT direction, which this ticket is not, and
`ShortDateFormat` only earned its place here because the parser reads it — a
setting nothing honours would be a lie. Filed separately if a consumer wants it.

## Log
- 2026-08-15 — resolved, commit cb42c7c51.
