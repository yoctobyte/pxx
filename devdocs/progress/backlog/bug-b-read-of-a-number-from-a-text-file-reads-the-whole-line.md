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
