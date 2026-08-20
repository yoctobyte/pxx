---
track: B
prio: 45
type: feature
blocked-by: []
summary: "Measured inventory: 22 sysutils/strutils/dateutils routines plus 3 type/alias names that FPC accepts and pxx rejects with `undefined variable`. Everything pxx DOES implement in this surface was verified byte-identical to FPC, so the gap is coverage, not correctness — a directory-walking or PChar-using program simply does not compile."
status: backlog
owner: unassigned
---

# 22 sysutils/strutils symbols FPC has and pxx does not

- **Track B** (`lib/rtl`). Found 2026-08-20 by an FPC differential probe of the
  string/file/date surface.
- Companion finding to the good news below — this is a **coverage** ticket, not
  a correctness one.

## First, what is already right

A 35-row probe of the implemented string surface (`su1.pas` in the session
scratch) came back **byte-identical to FPC**, including the cases that usually
differ: `Copy` past the end / with count 0 / with start 0, `StringReplace` with
`rfIgnoreCase`, `CompareStr` sign, `IntToHex(-1,8)`, `Format` with a negative
width, `QuotedStr` doubling. So nothing below is a behaviour difference — each
one is a symbol that is simply absent.

## Measured

Method: for each candidate, one program that *calls* it in its FPC signature,
compiled by `fpc -O- -Mobjfpc` and by pxx at `35b69f6e3`. Listed only where FPC
compiled clean and pxx said `undefined variable`.

**Note on method:** an earlier pass probed with `@Name` and produced six false
positives — `Sqr`, `Odd`, `Trunc`, `Round`, `Frac`, `Int` are intrinsics, and
FPC refuses `@` on them too. They are fine; they are not in the list.

| group | missing |
| --- | --- |
| PChar family (`strings`) | `StrCopy`, `StrComp`, `StrScan`, `StrPCopy`, `StrNew`, `StrDispose` |
| string search / words | `AnsiPos`, `AnsiSameStr`, `WordCount`, `ExtractWord` |
| directories | `CreateDir`, `RemoveDir`, `GetCurrentDir`, `SetCurrentDir`, `ExpandFileName`, `RenameFile` |
| date/time formatting | `DateToStr`, `TimeToStr`, `DateTimeToStr`, `GetTickCount64`, `FileGetDate` |
| float parsing | `TextToFloat` (probe's call shape was rejected by FPC too — confirm the signature before implementing) |

Also missing, and each one stops a program at its `var` line rather than at a
call, so they read as worse than they are:

- **`TStringArray`** — and with it `SplitString`, whose result type it is.
  These two go together; `SplitString('a,b,,c', ',')` is the idiom this blocks.
- **`TProcedure`** — the parameterless procedure type. A workaround is one
  line (`type TProc0 = procedure;`), but every FPC example that takes a
  callback uses the RTL name.

`StrLen` and `StrPas` ARE present, which is what makes the PChar row worth
doing as a set: the family is half there, so code reaches for it and then hits
a wall on the second call.

## Suggested split

The rows are independent; take them a group at a time rather than as one lump.
The PChar family and `TStringArray`+`SplitString` are the two that most often
stop real code. Related, already filed: `feature-lib-strutils-ansi-predicate-family`,
`feature-lib-sysutils-strtodate-and-strtodatetime`, `feature-sysutils-decodedate-missing`.

## Gate

Track B: build with `$(PXX_STABLE)`, `make lib-test` / `demos`. Each group
lands with an FPC-differential test — the probe above is the shape: call it,
print it, diff against `fpc -O-`.
