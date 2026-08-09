---
track: B
prio: 50
type: feature
summary: "lib/rtl/textfile.pas needs TextReadChar(var f; var c) with one-character pushback, so read(f, c) can consume ONE character like FPC instead of a whole line"
owner: claude-B
---

# `TextReadChar` with pushback, so `read(f, c)` means what FPC means

- **Type:** feature — Track B (`lib/rtl/textfile.pas`)
- **Status:** done
- **Opened:** 2026-08-05
- **Filed by:** Track A, splitting
  `bug-p-read-text-file-into-a-char-segfaults`. Track A owns the lowering and
  fixed the crash there; the RTL half is Track B's file, so it is handed over
  rather than done in place.

## What is missing

`lib/rtl/textfile.pas` reads **lines** only — `TextReadLn(var f; var s)`. Its
own header in the parser says so: *"v1 is line-oriented; read and readln map to
the same line read."*

FPC's `read(f, c)` consumes **one character** and leaves the rest of the line.
So `read(f, c)` currently has nothing correct to lower to, and Track A made it a
compile error rather than approximate it:

    error: read(Text): reading into a Char is not supported yet — read into a
           string and index it

## Why the obvious approximation was rejected

A Char arm that reads a LINE and takes `[1]` matches FPC for the first read and
is wrong for the second — it would return the next line's first character where
FPC returns the second character of this one. A character loop, which is the
main reason to read a Char at all, would silently skip the rest of every line.
That trades a crash for a silent wrong answer, so it was not done.

## Shape

`procedure TextReadChar(var f: Text; var c: Char);` with a one-character
pushback (or a buffered read position) in the `Text` record, so `TextReadLn`
and `TextReadChar` agree about where the cursor is when they are interleaved —
`read(f, c); readln(f, s);` must give the rest of the line in `s`.

Gate: FPC parity on the interleaved shapes, measured with
`tools/fpc_diff_probe.sh` — `read` then `readln`, a `while not Eof(f)` character
loop, and reading across a line boundary (FPC yields the newline as a character).

## Unblocks

`bug-p-read-text-file-into-a-char-segfaults` — once this exists, Track A adds the
Char arm in `ParseTextReadRest` that routes to it and removes the error. The
write-side twin (`bug-p-writeln-text-rejects-char`, fixed) shows the arm shape.

## Log
- 2026-08-09 — resolved, commit 56b177f0b.
