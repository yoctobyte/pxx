---
track: B
prio: 50
type: bug
owner: track-b-bughunt
blocked-by: []
summary: "StrToFloat('nope') returned 0 where FPC raises EConvertError — the integer arms of the family (StrToInt/StrToInt64/StrToQWord) were migrated to raising and the FLOAT arms were left behind, so garbage user input became a plausible number. Separately, the parser skipped leading SPACES only, so StrToFloat('1.5 ') and StrToFloat(#9'1.5') were REJECTED where FPC accepts them: FPC trims any char <= ' ' from both ends. Two defects, same routine."
status: done
---

# `StrToFloat` returns 0 for garbage, and rejects trailing whitespace

- **Type:** bug (silent wrong value + wrong rejection) — **Track B**
  (`lib/rtl/sysutils.pas`).
- Found 2026-08-14 by an FPC 3.2.2 differential sweep of the conversion and
  exception surface.
- The first half is the exact pattern
  `devdocs/dev/normalise-dont-special-case.md` warns about: **a double case
  where one arm was fixed and the sibling forgotten.** `StrToQWord`'s own
  comment in this file reads *"FPC parity: raises EConvertError on malformed
  input (used to return 0)"* — the integer arms were migrated, the float arms
  were not.

## Measured — pxx vs FPC 3.2.2

### 1. Malformed input silently returns 0

| | before | FPC |
| --- | --- | --- |
| `StrToInt('nope')` | raises | raises |
| `StrToInt64('nope')` | raises | raises |
| `StrToQWord('nope')` | raises | raises |
| `StrToBool('nope')` | raises | raises |
| **`StrToFloat('nope')`** | **0** | `EConvertError` |
| **`StrToFloat('')`** | **0** | `EConvertError` |
| **`StrToFloat('1.2.3')`** | **0** | `EConvertError` |
| **`StrToFloat('1e')`** | **0** | `EConvertError` |
| **`StrToCurr('nope')`** | **0** | `EConvertError` |

Every integer arm was already right; every float arm was wrong. `0` is the
dangerous answer — a plausible number the caller carries on with, the same shape
as `Floor(1e30) = 0` in
[[bug-b-floor-of-an-out-of-range-double-returns-0-where-fpc-raises]].

FPC's message is `"%s" is an invalid float`, and it is the same for `StrToCurr`
— verified rather than assumed, since callers match on message text.

### 2. Valid input wrongly rejected

The parser skipped leading `' '` and nothing else:

| input | before | FPC |
| --- | --- | --- |
| `' 1.5'` | 1.5 | 1.5 |
| **`'1.5 '`** | **rejected** | 1.5 |
| **`'  1.5  '`** | **rejected** | 1.5 |
| **`#9'1.5'`** | **rejected** | 1.5 |
| **`'1.5'#9`** | **rejected** | 1.5 |
| **`' 1.5e2 '`** | **rejected** | 150 |
| `'1. 5'`, `'1.5x'`, `'x1.5'`, `'   '`, `''` | rejected | rejected |

**FPC's whitespace is any char `<= ' '`**, measured rather than guessed: `#0`,
`#1`, `#11` and `#12` around a float are all accepted there. That is exactly
`Trim`'s rule, which this RTL already implements FPC-compatibly.

The two halves interact: with `StrToFloat` returning the default silently, a
rejected-but-valid `'1.5 '` also came back as **0** rather than as an error.

## Fix

- `StrToFloatDef` parses `Trim(s)` instead of `s`, and the leading-space loop
  goes away — one rule where there were two, and it is the measured one.
- `StrToFloat` raises `EConvertError.CreateFmt('"%s" is an invalid float', [s])`
  when `TryStrToFloat` fails, matching `StrToInt64`'s existing shape line for
  line. `StrToCurr` inherits it by delegation.
- The interface comment claiming *"StrToFloat returns 0"* was documenting the
  bug; it now says it raises.

`TryStrToFloat` and `StrToFloatDef` keep their non-raising contract, and pick up
the whitespace fix — which is what callers wanting the old leniency should use.

## Callers checked

`lib/rtl/json.pas` (a number the JSON parser already validated),
`lib/rtl/ast.pas` (a lexed float literal) and `test/lib_floattostr.pas`
(round-trips of generated text) all pass well-formed input, so the raise cannot
fire for them. For `json.pas` the raise is strictly better than a silent 0.

## Gate

All five probe programs identical to FPC — the conversion family (14 rows), the
whitespace grammar (17 rows), the control-character cases (6 rows), the message
text (4 rows) and the exception surface (16 rows) — plus `make lib-test` green.

## Log
- 2026-08-14 — resolved, commit 7fc1c25e1.
