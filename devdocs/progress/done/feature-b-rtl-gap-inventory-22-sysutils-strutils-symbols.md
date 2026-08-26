---
track: B
prio: 75
type: feature
blocked-by: []
summary: "Measured inventory: 22 sysutils/strutils/dateutils routines plus 3 type/alias names that FPC accepts and pxx rejects with `undefined variable`. Everything pxx DOES implement in this surface was verified byte-identical to FPC, so the gap is coverage, not correctness — a directory-walking or PChar-using program simply does not compile."
status: done
owner: frank1-B-rtl
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

## Log
- 2026-08-26 — resolved, commit f41c0c42f (the RTL work; write-up in 92f68eea3).

## Resolution (2026-08-26, frank1-B-rtl)

**All 22 routines and all 3 type names landed.** The inventory was re-verified
against the pinned stable before implementing rather than trusted: it was
accurate except for one row — `StrCopy`/`StrComp`/`StrScan` *did* exist, in
`lib/rtl/strings.pas`, and were missing only from **SysUtils**, which is the
unit real FPC code names. That is now fixed too, so the row's premise (the
family is half there) held even though three of its six entries did not.

Everything below was MEASURED by compiling the same program under
`fpc -O- -Mobjfpc -Sh` and under pxx and diffing the output. A 103-line
differential probe covering the whole set came back **byte-identical**.

| group | landed |
| --- | --- |
| PChar family | `StrPCopy` `StrPLCopy` `StrECopy` `StrMove` `StrUpper` `StrLower` `StrAlloc` `StrBufSize` `StrNew` `StrDispose` in `strings`, plus the whole family re-exported from `sysutils` |
| search / words | `AnsiPos` `AnsiSameStr` `SameStr` `WordCount` `WordPosition` `ExtractWord` `ExtractWordPos` `ExtractDelimited` `ExtractSubstr` |
| directories | `CreateDir` `RemoveDir` `ForceDirectories` `GetCurrentDir` `SetCurrentDir` `ExpandFileName` `RenameFile` |
| date/time | `DateToStr` `TimeToStr` `DateTimeToStr` (both arities) `GetTickCount64` `GetTickCount` `FileGetDate`, plus `LongTimeFormat` / `ShortTimeFormat` / `LongDateFormat` |
| float | `TextToFloat` (`var Value: Extended`, FPC's signature — a `Double` var still binds) |
| types | `TStringArray` `TStringDynArray` `TProcedure` `TFloatFormat` |
| beyond the inventory | FPC's **four-argument `FloatToStrF`**, which was a compile error here |

### The contracts a plausible implementation gets wrong

These are why the ticket asked for measurement, and each one was measured:

- `StrNew('')` and `StrNew(nil)` are **nil** — not an empty allocated buffer.
- `StrECopy` returns the cursor at the terminating NUL, **not** `Dest`.
- `StrBufSize(StrNew('abc'))` is **4** (len+1), not a rounded capacity.
- `CreateDir` on an **existing** directory is **False**; only
  `ForceDirectories` is idempotent.
- `GetCurrentDir` has no trailing slash; `ExpandFileName('')` is the cwd
  **with** one.
- `ExpandFileName` collapses `.`/`..` lexically on paths that do not exist, but
  a **leading `//` survives** (POSIX reserves it) where every other slash run
  collapses.
- `DateToStr` is `7-3-20`, not ISO: `/` in a format string means
  `DateSeparator` (default `-`) and a lone `y` is a two-digit year.
- `DateTimeToStr` **drops the time half at exact midnight** — once a day a log
  line loses its clock. Milliseconds do not bring it back.
- `TextToFloat` trims surrounding blanks but rejects trailing junk: `'1.5x'` is
  False, not 1.5.
- Three *different* split models disagree on `a,b,,c`: `ExtractWord` gives
  a/b/c, `ExtractDelimited` gives a/b/''/c, `ExtractSubstr` gives a/b/c/''.
- `SplitString`'s second argument is ONE multi-character separator in FPC
  3.2.2, not a character set: `'a1b2c'` split on `'12'` comes back whole.

### One deliberate divergence, escalated

FPC ships **two incompatible `StrAlloc`s** — `strings` allocates prefix-free,
`sysutils` with a 4-byte size prefix — so `uses SysUtils, Strings` pairs the
first with the second's `StrBufSize`/`StrDispose`. Measured: that reads
4294967292 and frees `p-4`. We ship **one** implementation; single-unit
programs (i.e. all of them) see exactly FPC, and only the programs FPC corrupts
can tell the difference. Filed for the owner as
`decide-stralloc-one-implementation-or-fpcs-two`.

### Compiler bugs found, none worked around in `lib/rtl`

- `bug-single-char-literal-as-pchar-argument-segfaults` — **pre-existing and
  the worst of the three**: `StrCat(buf, '-')` faults where `'--'` works,
  because a one-char literal passes its ordinal as the pointer. Reachable
  through `StrCopy`/`StrCat`, which have been here all along; nothing had ever
  passed a single character to them.
- `bug-pchar-difference-in-writeln-arg-segfaults`
- `bug-dynarray-function-result-passed-directly-types-as-pointer` — blocks the
  `Dump(SplitString(line, ','))` idiom.

Only the tests were adjusted around these (documented in place, with the slug
to revert at); no library code was reshaped.

### Parked

`bug-b-f-fixed-point-rounding-of-a-tie-goes-down-where-fpc-goes-up` — the one
row of twenty where `FloatToStrF` differs from FPC. Pre-existing in `FmtFixed`
and already reachable through `Format('%.2f')`; last-digit-only, so Track F by
definition (`devdocs/progress/float/`).

### Tests

`test/lib_strings_pchar.pas`, `test/lib_strutils_words.pas`,
`test/lib_sysutils_dirs_dates.pas` — wired into `lib-test`. All three **compile
and pass under FPC as well as pxx**, which is what makes them oracles rather
than recordings of our own behaviour.

Gate: `make lib-test` green end to end. The one failure in that target,
`MIMIC-XML-ETREE`, is pre-existing and unrelated — verified by reverting these
three RTL files and watching it fail identically; it is already held in
`working/bug-n-a-callable-value-reaches-a-str-parameter-and-renders-as-bound-method`.
