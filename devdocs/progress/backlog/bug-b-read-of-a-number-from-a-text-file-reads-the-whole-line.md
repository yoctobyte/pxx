---
track: B
prio: 65
type: bug
blocked-by: []
summary: "`read(f, n)` / `readln(f, n)` on a Text file reads the whole LINE and Vals it, so any line with two numbers, or one number plus trailing spaces, silently yields 0. `readln(t, n, m)` on '42 3' gives 0 0 where FPC gives 42 3. Works only when the line holds exactly one number and nothing else."
status: backlog
---

# `read(f, number)` from a Text file reads the whole line

Found 2026-08-20 by an FPC differential probe over file I/O.

## The measurement

`fpc -O- -Mobjfpc` 3.2.2 vs pxx at `242902fc6`. Every failing row yields **0**
— no error, no exception, no diagnostic.

| file content | statement | FPC | pxx |
| --- | --- | --- | --- |
| `42` | `readln(t, n)` | 42 | 42 |
| `   42` | `readln(t, n)` | 42 | 42 |
| `42  ` (trailing spaces) | `readln(t, n)` | 42 | **0** |
| `42 3` | `readln(t, n, m)` | 42 3 | **0 0** |
| `42 3` | `read(t, n); read(t, m)` | 42 3 | **0 0** |
| `42` / `3` (two lines) | `read(t, n); read(t, m)` | 42 3 | 42 3 |
| `2.5` | `readln(t, d)` | 2.50 | 2.50 |
| `42 abc` | `read(t, n); readln(t, s)` | `42[ abc]` | **`0[]`** |

So it works for exactly one shape — one number alone on its line — and fails
silently for every other. Reading a table of numbers, the single most common
reason to open a text file, returns all zeros.

## Root cause

`ParseTextReadRest` (`compiler/parser.inc`) lowers a numeric destination to
`TextReadLn` into a hidden string, then `Val` into the destination:

```
TextReadLn(f, tmp);        { reads the WHOLE line }
Val(tmp, dest, code);      { fails on "42 3" or "42  " -> code<>0, dest untouched }
```

`Val` requires the string to be the number and nothing else, so any second
token or trailing blank makes it fail, and the failure is discarded — the
destination keeps whatever it had, which for a fresh variable is 0. The comment
on that arm explains why it reads a line (the dest slot used to be handed to
`TextReadLn` as an AnsiString and got corrupted), so the line-read was a fix for
a worse bug, not a design.

FPC reads one numeric TOKEN: skip whitespace *including line breaks*, take the
number, leave the cursor immediately after it.

## The fix

`lib/rtl/textfile.pas` already has the one byte of pushback a tokeniser needs —
`f.Peek` / `f.HasPeek`, which `Eof` fills and `TextReadLn` / `TextReadChar`
drain. So:

1. **RTL (Track B):** add `procedure TextReadNumTok(var f: Text; var s: AnsiString)`.
   Skip `' '`, `#9`, `#10`, `#13` (and stop cleanly at EOF, where `TextReadChar`
   yields `#26`), collect non-whitespace into `s`, then push the delimiter back
   via `f.Peek := Byte(c); f.HasPeek := True`. Whitespace-delimited tokenising
   matches FPC for all valid numeric input; `42abc` is a runtime error 106 in
   FPC and would `Val`-fail here, which is a divergence worth stating in the
   ticket that lands it, not worth extra machinery.
2. **Frontend (Track P):** the numeric arm of `ParseTextReadRest` calls
   `TextReadNumTok` instead of `TextReadLn`.
3. **Frontend, do not miss this:** the same function emits the end-of-line skip
   for `readln` only when the last destination was the **char** arm, on the
   grounds that "the string and numeric arms already consume the terminator
   (TextReadLn eats it)". Once the numeric arm stops reading a line, that stops
   being true — the skip must fire for a numeric last destination too, or
   `readln(t, n)` will leave the cursor mid-line.

Track B owns `lib/rtl`, Track P owns the parser, so this is a B+P item; filed
under B because the new primitive is the substantive half.

## Not affected

The rest of the text-file probe matches FPC line for line: `Rewrite`/`Reset`/
`Append`, `writeln(t, ...)` with mixed argument types, `readln(t, s)`, `Eof`
loops, line counts across an append, `read(t, c)` for a Char followed by
`readln(t, s)` for the rest of the line, `FileExists` and `DeleteFile`.

Typed and untyped files (`file of TRec`, `file`) are separately filed as
`feature-pascal-typed-and-untyped-files` and were not exercised here.

## Appendix (2026-08-22) — the STRING arm has the same defect, and it is the same shortcut

Re-measured against `fpc -Mobjfpc -O1` 3.2.2 vs pxx at `a38f1cf8a`, in a file-I/O
differential sweep. The number arm above is one of two symptoms of the same line-read
shortcut: **`read(f, s)` for a string destination is indistinguishable from
`readln(f, s)`.**

File is `L1`/`L2`/`L3`, one per line:

| statement | FPC | pxx |
| --- | --- | --- |
| `read(f, s)` | `L1`, then `Eoln(f)` = TRUE | `L1`, then `Eoln(f)` = **FALSE** |
| `read(f, s)` again | `` (empty — cursor is parked at the eoln) | **`L2`** |
| `readln(f); read(f, s)` | `L2` | **`` (empty; already at EOF)** |

FPC's `read(f, s)` reads *to* the line terminator and stops **before** it, so
repeating it yields the empty string forever until a `readln` steps over the
terminator. pxx swallows the terminator, so each `read` advances a line and the
program silently reads the wrong lines — the classic `read(f, s); readln(f)` idiom
skips every other line.

Root cause is one line of `ParseTextReadRest` (`compiler/pasparser_stmt.inc`), the
`else` (string) arm:

```pascal
callNode := GenMakeCall6(procRead, tyUnknown, GenMakeIdent(fileSym, tyRecord),
                         destNode, -1, -1, -1, -1);   { procRead = TextReadLn }
```

`TextReadLn` eats the terminator by definition, and the function's own comment
below the loop already *relies* on that (`the string and numeric arms already
consume the terminator (TextReadLn eats it)`, which is why `readln` emits no extra
skip after them). So the string arm is correct for `readln` and wrong for `read`;
the two spellings currently lower identically.

### What this means for the fix above

The RTL half the fix section proposes — one-byte pushback tokenising over
`f.Peek` / `f.HasPeek` — serves **both** arms, so do them together:

- `TextReadStrTo(var f: Text; var s: AnsiString)` — read up to but NOT over the
  terminator; at an eoln return `''` without advancing. This is `read`'s string arm.
- `TextReadNumTok` as already specified — `read`'s and `readln`'s numeric arm.
- `TextReadLn` keeps its current meaning and stays `readln`'s string arm.

Then `ParseTextReadRest`'s trailing-skip logic changes with it: once `read`'s arms
no longer consume the terminator, `readln` must emit the skip after **every**
destination kind, not only after the char arm. That comment block is the map of
what to re-measure — its FPC-measured rows (`'ab'#10'cd'#10` giving `'a'` then
`'c'`) are the regression cases.

Also note the `read(f, c)` char arm is already correct (`TextReadChar` does not
swallow the terminator) — it is the one arm that was written against the real FPC
behaviour, which is why it needed a special case in the trailing-skip logic. After
this fix the special case disappears and all three arms behave alike. That
collapse is the tell that this is a root-cause fix and not three microfixes:
`devdocs/dev/normalise-dont-special-case.md`.
