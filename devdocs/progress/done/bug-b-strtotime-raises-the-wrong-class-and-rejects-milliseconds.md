---
track: B
prio: 45
type: bug
owner: track-b-bughunt
blocked-by: []
summary: "StrToTime raised a bare Exception where FPC raises EConvertError, so the `on E: EConvertError do` handler every caller writes around a parse walked straight past it — the catch is there, it just never fires. It also rejected milliseconds: StrToTime('13:05:09.250') raises here, parses there. Fixing the second needed the rule MEASURED, not read: FPC's fraction is a millisecond FIELD, so '.25' is 25 ms and not 250."
status: done
---

# `StrToTime` raises the wrong class, and rejects milliseconds

- **Type:** bug (uncatchable exception + wrong rejection) — **Track B**
  (`lib/rtl/sysutils.pas`).
- Found 2026-08-14 by an FPC 3.2.2 differential sweep, continuing the
  conversion-family sibling grep that produced
  [[bug-b-strtofloat-returns-0-for-malformed-input-and-rejects-trailing-space]].

## 1. The exception class — the half that matters

| input | before | FPC |
| --- | --- | --- |
| `'nope'` | `Exception` | **`EConvertError`** |
| `''` | `Exception` | `EConvertError` |
| `'25:00:00'` | `Exception` | `EConvertError` |
| `'13:99:00'` | `Exception` | `EConvertError` |
| `'13:05x'` | `Exception` | `EConvertError` |

`on E: EConvertError do` is the handler an FPC or Delphi caller writes around a
parse. A bare `Exception` is not that class, so the handler **does not fire** and
the exception escapes to whatever catches `Exception` — or to the top. The
failure mode is a program that looks correctly defensive and is not.

Every other arm of this family (`StrToInt`, `StrToInt64`, `StrToFloat`,
`StrToQWord`) already raised `EConvertError`; this one was the odd arm out — the
same "one arm of a double case was fixed and the sibling forgotten" shape as the
`StrToFloat` ticket above.

FPC's message is `"%s" is not a valid time` — note it differs in wording from the
integer arms' `"%s" is an invalid integer`. Matched exactly, since callers match
on message text.

## 2. Milliseconds — and the rule is NOT what it looks like

`StrToTime('13:05:09.250')` raised here and parses in FPC. The obvious
implementation is a decimal fraction of a second. **Measured, that is wrong:**

| input | decimal-fraction reading | FPC (measured) |
| --- | --- | --- |
| `'13:05:09.250'` | 250 ms | 250 ms |
| `'13:05:09.25'` | 250 ms | **25 ms** |
| `'13:05:09.2'` | 200 ms | **2 ms** |
| `'13:05:09.1234'` | 123 ms (truncate) | **raises** |
| `'13:05.5'` | 500 ms | **raises** |

So FPC's fraction is a **millisecond field**, read as a plain integer: at most
three digits, a fourth is an error rather than a truncation, and it is only
allowed after a full `h:m:s`. `'.25'` means 25 ms.

This ticket exists partly as a record of that: the padding implementation was
written, and only the differential probe caught it — three of the five rows
above would have shipped wrong, silently, as *times off by a factor of ten or a
hundred*.

## Fix

- One `Bad` local raising `EConvertError.CreateFmt('"%s" is not a valid time', [S])`,
  replacing three inline `raise Exception.Create` sites.
- A fraction branch gated on `np = 2` (h:m:s seen) and `digits > 0`, reading the
  digits as an integer, rejecting a fourth, and rejecting a separator with no
  digits after it.

## Gate

Two probes identical to FPC — the basic surface (10 rows: h/h:m/h:m:s, ms,
malformed, empty, out-of-range hour and minute, surrounding spaces, trailing
junk) and the fraction edges (13 rows: 1/2/3/4 fraction digits, a bare
separator, a fraction after `h:m`, `.5` alone, `00:00:00.001`, `23:59:59.999`,
and the message text on every raising row). `make lib-test` green.

## Still missing from this family — filed separately

`StrToDate`, `StrToDateTime` and the `TryStrTo*` date variants do not exist in
this RTL at all; only `StrToTime` does. See
[[feature-lib-sysutils-strtodate-and-strtodatetime]].

## Log
- 2026-08-14 — resolved, commit e95f54ee7.
