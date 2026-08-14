---
track: B
prio: 25
type: feature
blocked-by: []
summary: "lib/rtl/strutils is missing the Ansi* predicate family FPC and Delphi ship — AnsiContainsStr/Text, AnsiStartsStr, AnsiEndsStr, AnsiIndexStr, AnsiReplaceStr — plus AddChar/AddCharR. PadLeft/PadRight are already there, so this is a gap in one corner rather than a missing unit. Found when a differential sweep against FPC would not compile until they were deleted from the probe."
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
