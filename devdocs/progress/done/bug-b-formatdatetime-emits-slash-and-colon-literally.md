---
track: B
prio: 40
type: bug
owner: track-b-bughunt
blocked-by: []
summary: "FormatDateTime copied '/' and ':' through as literal characters. Delphi and FPC define them as the DATE and TIME separator placeholders, so they render DateSeparator/TimeSeparator. With DateSeparator '.', FPC gives 14.08.26 for 'dd/mm/yy' where pxx gave 14/08/26 whatever the setting was — a caller that set the separator for a locale had its format string silently ignored. The ':' half looked correct only because the default happens to be ':'."
status: done
---

# `FormatDateTime` emits `/` and `:` literally instead of the separators

- **Type:** bug (wrong output) — **Track B** (`lib/rtl/sysutils.pas`).
- Found 2026-08-14 by an FPC differential sweep of rounding, math and date
  formatting — 35 rows, of which this was the only divergence.

## Measured — pxx vs FPC 3.2.2

```pascal
d := EncodeDate(2026,8,14) + EncodeTime(13,5,9,0);
DateSeparator := '.'; TimeSeparator := '_';
WriteLn(FormatDateTime('dd/mm/yy', d));
WriteLn(FormatDateTime('hh:nn:ss', d));
WriteLn(FormatDateTime('yyyy/mm/dd hh:nn', d));
WriteLn(FormatDateTime('dd"/"mm', d));        { quoted — must stay literal }
```

| format | separators | before | FPC |
| --- | --- | --- | --- |
| `dd/mm/yy` | `-` / `:` | 14/08/26 | **14-08-26** |
| `dd/mm/yy` | `.` / `_` | 14/08/26 | **14.08.26** |
| `hh:nn:ss` | `-` / `:` | 13:05:09 | 13:05:09 |
| `hh:nn:ss` | `.` / `_` | 13:05:09 | **13_05_09** |
| `yyyy/mm/dd hh:nn` | `.` / `_` | 2026/08/14 13:05 | **2026.08.14 13_05** |
| `dd"/"mm` | any | 14/08 | 14/08 |

The `:` row is the instructive one: it agreed at the default and diverged the
moment `TimeSeparator` moved. A test using only default settings would have
called that half green forever — which is presumably how it survived.

The quoted row is right in both and must stay that way: `"/"` is a literal, only
a bare `/` is the placeholder.

## Cause

The token loop handled `y m d h n s z`, quoted runs, and then had a single
`else` copying every other character straight through. `/` and `:` are not
literals in this format language — Delphi and FPC define them as *"the date
separator character"* and *"the time separator character"*, which is why
`FormatSettings` carries `DateSeparator`/`TimeSeparator` at all.

Both globals already existed here (`lib/rtl/sysutils.pas` ~line 269, defaulted
to `-` and `:`); nothing read them in this routine.

## Fix

Two branches before the literal fallback, emitting `DateSeparator` and
`TimeSeparator`. Six lines, no restructuring, and quoted runs are untouched
because they are consumed earlier in the loop.

**Visible change at the default settings:** `DateSeparator` defaults to `-`
here, so `FormatDateTime('dd/mm/yy', …)` now yields `14-08-26` where it used to
yield `14/08/26`. That is the correct behaviour and matches FPC on this box, but
it is a behaviour change for any caller that wrote `/` meaning a literal slash —
they should quote it as `"/"`, which is what the format language requires and
what FPC has always required.

## Gate

The table above matches FPC on every row, and `make lib-test` green.

## Log
- 2026-08-14 — resolved, commit d2d5d8a48.
