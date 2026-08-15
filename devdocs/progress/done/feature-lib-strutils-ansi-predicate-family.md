---
track: B
prio: 25
type: feature
blocked-by: []
summary: "lib/rtl/strutils is missing the Ansi* predicate family FPC and Delphi ship — AnsiContainsStr/Text, AnsiStartsStr, AnsiEndsStr, AnsiIndexStr, AnsiReplaceStr — plus AddChar/AddCharR. PadLeft/PadRight are already there, so this is a gap in one corner rather than a missing unit. Found when a differential sweep against FPC would not compile until they were deleted from the probe."
status: done
owner: track-b-bughunt
---

# `strutils`: the `Ansi*` predicate family is missing

- **Type:** feature (library gap) — **Track B** (`lib/rtl/strutils.pas`).
- Found 2026-08-14 while writing an FPC differential sweep: the probe would not
  compile against pxx until each of these was removed, one error at a time. The
  31 rows that *did* compile all matched FPC exactly, so this is a surface gap
  and not a correctness problem.

## Missing, all present in FPC 3.2.2 and Delphi

| name | what it does |
| --- | --- |
| `AnsiContainsStr(s, sub)` | case-**sensitive** substring test |
| `AnsiContainsText(s, sub)` | case-**insensitive** substring test |
| `AnsiStartsStr(prefix, s)` | prefix test (note the argument order — prefix first) |
| `AnsiEndsStr(suffix, s)` | suffix test |
| `AnsiIndexStr(s, array)` | index of the first exact match, or -1 |
| `AnsiReplaceStr(s, old, new)` | `StringReplace` with `[rfReplaceAll]` |
| `AddChar(c, s, n)` | left-pad `s` with `c` to length `n` |
| `AddCharR(c, s, n)` | right-pad |

Already present, which is why this reads as a corner rather than a hole:
`PadLeft`, `PadRight`, `DupeString`, `PosEx`, `ReverseString`, `IfThen`.

## Notes for whoever takes it

- **Argument order is a trap.** `AnsiStartsStr(ASubText, AText)` takes the
  *prefix* first, the opposite of the reading order most people assume, and the
  same for `AnsiEndsStr`. Get it from FPC's declaration, not from intuition.
- `AddChar`/`AddCharR` **do not truncate**: if `s` is already longer than `n`
  the string comes back unchanged. Worth an explicit test row, since a
  "pad to width" implementation that truncates is the obvious wrong guess.
- `AnsiIndexStr` returns **-1** when absent, not 0 — it is an array index, not a
  `Pos`.
- Each is a thin wrapper over something already in `sysutils`
  (`Pos`, `CompareText`, `Copy`, `StringReplace`), so the work is the
  declarations, the argument order, and a differential test against FPC — not
  new algorithms.

## Gate

A `.pas` covering all eight against FPC 3.2.2, including empty strings, an
absent needle, a needle equal to the haystack, and the no-truncate case, plus
`make lib-test` green.

## Resolution (2026-08-15)

Twelve functions landed in `lib/rtl/strutils.pas` — the eight above plus the
`...Text` twins FPC also ships and the ticket did not list: `AnsiStartsText`,
`AnsiEndsText`, `AnsiIndexText`, `AnsiReplaceText`. A probe with a `...Str`
but no `...Text` twin is the same surface gap one call later.

A 27-row probe was diffed against FPC 3.2.2 (`{$mode objfpc}{$H+}`) and matches
on every row. Three contracts were **measured, not assumed**, and each is now a
comment in the source next to the code it explains:

- `AnsiContainsStr('hello', '')` is **FALSE** — FPC's `Pos('', s)` is 0 —
  while `AnsiStartsStr('', 'hello')` and `AnsiEndsStr('', 'hello')` are both
  **TRUE**. The empty needle is *not* handled uniformly across the family. That
  looks like an inconsistency worth smoothing over; smoothing it over is how
  you diverge from every real caller.
- `AnsiIndexStr` is case-sensitive and answers `-1`, its `Text` twin folds case.
- Neither `AddChar` nor `AddCharR` truncates, as the ticket predicted.

Test: 22 rows appended to `test/lib_strutil.pas` (37 -> 59 `=ok`), chosen as the
rows nobody guesses right rather than one per function — argument order, the
empty needle on both sides, `-1`-not-0, case sensitivity on each `Str`/`Text`
pair, and the no-truncate case.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
