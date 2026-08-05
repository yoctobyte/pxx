---
track: A
prio: 55
type: bug
summary: "read(f, c) for a Char destination on a Text file SEGFAULTS — the Char slot is handed to TextReadLn, which expects an AnsiString var, so a string handle is written into one byte. FPC reads the character"
owner: claude-A
---

# `read(f, c)` into a Char from a Text file segfaults

- **Type:** bug — Track A (builtin lowering) / Track P
- **Status:** working
- **Opened:** 2026-08-05
- **Found by:** Track A, immediately after fixing the write-side twin
  `bug-p-writeln-text-rejects-char`. **Pre-existing** — `pinned` segfaults
  identically.

## Repro

```pascal
var f: Text; c: Char;
begin
  Assign(f, 'somefile'); Reset(f);
  read(f, c); writeln('char=', c);
  Close(f);
end.
```

    FPC : char=h
    pxx : SIGSEGV

## Cause — the same exclusion as the write side, opposite consequence

`ParseTextReadRest` in `compiler/parser.inc` gates its numeric path on

```pascal
if TypeIsFloat(trTk) or (TypeIsOrdinal(trTk) and (trTk <> tyChar)) then
```

so a `Char` destination falls into the `else`, which passes the destination
**straight to `TextReadLn(f, dest)`** — a routine whose second parameter is a
`var AnsiString`. A string handle is written into a one-byte Char slot.

Exactly the same `(trTk <> tyChar)` exclusion that made the WRITE side reject a
Char (fixed: it now routes through a new `StrChar`). Here the fall-through is not
an error but memory corruption, which is why this one is the more urgent half.

## The design question the fix has to answer

pxx's Text read is **line-oriented** — the header says so: *"v1 is
line-oriented; read and readln map to the same line read."* FPC's `read(f, c)`
consumes ONE CHARACTER and leaves the rest of the line.

So a Char arm that reads a line and takes `[1]` fixes the crash and matches FPC
for the first read, but the SECOND `read(f, c)` would return the next line's
first character where FPC returns `'e'`. That is a real semantic gap, not a
detail — character-at-a-time input is the main reason to read a Char at all.

Two honest options:

1. **Char-level read** — give the textfile RTL a `TextReadChar(var f, var c)`
   with a one-character pushback/buffer, and route the Char arm to it. Correct,
   and it is what "read" means; costs a buffered-position concept in the Text
   record.
2. **Line-oriented approximation** — read a line, take the first character. Kills
   the segfault today, is right for the common `read(f, c)`-then-`readln(f)`
   shape, and is WRONG for a character loop. If chosen, reject or warn on the
   second Char read rather than silently returning the wrong thing.

Recommend (1); it is the only one that makes `while not Eof(f) do read(f, c)`
work, which is the case people write.

Until then the crash stands, and a compile-time error would be strictly better
than a segfault.

## Related

- `bug-p-writeln-text-rejects-char` — the write-side twin, fixed. Its `StrChar`
  helper and Char arm are the shape to mirror.


## PARTIAL 2026-08-05 — the segfault is now a diagnostic; the feature is Track B's

The crash is gone. `read(f, c)` on a Char destination is now a compile error
naming this ticket, instead of writing a string handle into a one-byte slot:

    error: read(Text): reading into a Char is not supported yet — read into a
           string and index it (bug-p-read-text-file-into-a-char-segfaults)

That is deliberately NOT the line-read-and-take-[1] arm. As set out above, that
shape is right for the first read and wrong for the second, and a character loop
— the main reason to read a Char — would silently skip the rest of every line.
Turning memory corruption into a silent wrong answer is not an improvement.

**The real fix stays open and is Track B's to land**: `TextReadChar(var f; var c)`
with one-character pushback in `lib/rtl/textfile.pas`, then a Char arm here that
routes to it. `lib/rtl/**` is Track B's lane, so this half was not taken.
Ticket stays open for that; only the crash is closed.

String reads are unaffected (`readln(f, s)` verified working), and the numeric
path is untouched.
