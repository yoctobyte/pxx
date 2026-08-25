---
track: B
prio: 65
type: feature
blocked-by: []
summary: "`SeekEof`, `SeekEoln`, `Rename` and `SetTextBuf` are absent from the Text surface — every one is `undefined variable` at compile time. `SeekEof`/`SeekEoln` are the whitespace-tolerant loop conditions ordinary token-reading code uses; `Rename` has its PAL entry point already (`PalRename`) and needs only the Text-handle wrapper."
status: backlog
---

# Four standard Text-file routines are missing

Found 2026-08-22 by an FPC differential sweep over file I/O (`fpc -Mobjfpc -O1`
3.2.2 vs pxx at `a38f1cf8a`).

## The measurement

Each of these is a compile-time `undefined variable`, not a wrong result:

| routine | pxx | note |
| --- | --- | --- |
| `Flush(f)` | **compiles** | already present |
| `SeekEof(f)` | `undefined variable (SeekEof)` | missing |
| `SeekEoln(f)` | `undefined variable (SeekEoln)` | missing |
| `Rename(f, 'new')` | `undefined variable (Rename)` | missing |
| `SetTextBuf(f, buf)` | `undefined variable (SetTextBuf)` | missing |

## Why these four matter, in order

**`SeekEof` / `SeekEoln` are the important pair.** They are not conveniences —
they are how a Pascal program reads a whitespace-separated table without
tripping on the blank tail of the last line:

```pascal
while not SeekEof(f) do begin Read(f, n); Sum := Sum + n; end;
```

`Eof(f)` is False while trailing blanks or a final newline remain, so the loop
above written with `Eof` reads one junk value at the end. Both routines skip
whitespace *without consuming the next real token* — which is exactly the
one-byte-pushback capability `lib/rtl/textfile.pas` already has in `f.Peek` /
`f.HasPeek`. `SeekEoln` additionally stops at the line terminator; `SeekEof`
skips over it.

That makes these two the natural companions of
`bug-b-read-of-a-number-from-a-text-file-reads-the-whole-line` (prio 65): that
ticket adds a numeric tokeniser over the same pushback, and these two are the
matching loop conditions. **Whoever takes that ticket should take this one in
the same pass** — same file, same mechanism, and the pair is what makes the
tokeniser usable.

**`Rename` is nearly free.** `PalRename` already exists
(`lib/rtl/platform.pas:117,369`) and `lib/rtl/pxxcio.pas:183` already calls it.
What is missing is only the `Rename(var f: Text; const NewName: string)`
wrapper that renames the file a handle is assigned to and updates the handle's
stored name. FPC requires the file be closed; do the same rather than inventing
a laxer rule.

**`SetTextBuf` is the least important** and may be a no-op stub. FPC's contract
is "use this caller-supplied buffer for this handle"; a stub that accepts and
ignores the buffer is a silent lie about lifetime, so either implement it or
leave it missing — a compile error is more honest than a routine that pretends.
That is a genuine fork, so if the taker disagrees with implementing it, file a
Track U `decide-*` rather than stubbing it.

## Scope

Track B (`lib/rtl/textfile.pas`, plus a `Rename` wrapper). No compiler change
is expected: `Flush(f)` already compiles, so the Text-handle dispatch path
accepts an RTL routine taking `var f: Text` without frontend work. If it turns
out `SeekEof` needs a parser arm the way `read`/`readln` do, that half is Track
P and should be filed separately.

## Gate

`make lib-test` plus a test whose expected output is FPC's, in the shape of the
existing text-file tests.
