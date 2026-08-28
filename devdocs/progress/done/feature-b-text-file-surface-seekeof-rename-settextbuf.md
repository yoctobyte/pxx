---
track: B
prio: 65
type: feature
blocked-by: []
summary: "`SeekEof`, `SeekEoln`, `Rename` and `SetTextBuf` are absent from the Text surface — every one is `undefined variable` at compile time. `SeekEof`/`SeekEoln` are the whitespace-tolerant loop conditions ordinary token-reading code uses; `Rename` has its PAL entry point already (`PalRename`) and needs only the Text-handle wrapper."
status: done
owner: frankB
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

## 2026-08-28 (frankB, Track B) — RESOLVED. Three of four implemented; `SetTextBuf` escalated as the ticket instructed.

No compiler change was needed, as predicted: `SeekEof`/`SeekEoln` declare like
`Eof` (`function(var f: Text): Boolean`) and `Rename` like `Erase`, and the Text
dispatch path took all three without a parser arm. Nothing was filed to Track P.

### The skip set is not what it looks like, and that is the whole finding

I measured it rather than assuming, and the obvious rule is wrong. An FPC 3.2.2
oracle wrote each of `#1`..`#40` in front of an `'x'` and read back where the
cursor landed. **Exactly three bytes are stepped over:**

```
skipped:      #9 TAB, #26 SUB, #32 SPACE      (SeekEof also skips #10 and #13)
NOT skipped:  #1..#8, #11, #12, #14..#25, #27..#31, #33 and up
```

So `c <= 32` — the rule anyone would reach for, and the one a later
"simplification" will reach for again — is **wrong**: it eats `#1`, `#31` and
every other control byte straight out of a data file. `#26` is in the set
because it is the DOS end-of-file marker and FPC steps over it like blank
space; measured both ways, a file holding only `#26` is `SeekEof`-empty while
`'x'#26` still yields its `'x'`.

The two routines then differ by exactly the line terminators: `SeekEof` skips
`#10`/`#13`, `SeekEoln` stops on them and answers True without consuming them,
so `Readln` still sees a whole line.

**Deliberately not unified with the existing `TFIsSpace`.** That is the numeric
tokeniser's *delimiter* set (`#9 #10 #13 #32`); this is the seek routines'
*skip* set. They overlap without being one concept — `#26` belongs only to the
second, and `#10`/`#13` delimit a token but must stop `SeekEoln` — so folding
them together would make one of the two wrong. Noted in the source at both
sites, because `normalise-dont-special-case.md` would otherwise read as an
argument to merge them.

### `Rename`

Mirrors `Erase` (a name-level operation on a closed, assigned handle) over the
existing `PalRename`. Measured on FPC and copied rather than relaxed: an **open**
handle is refused and the file left alone, and after a successful rename **the
handle follows the file** — `Reset(f)` opens the new name and reads its
contents. FPC's codes are 102 (open) and 2 (missing); ours stay ours per
`CLAUDE.md`'s runtime-error rule, and the test asserts *refused*, not a number.

### `SetTextBuf` — escalated, not stubbed

`lib/rtl/textfile.pas` has **no buffering at all**: one `PalRead` per byte, with
a one-byte pushback slot for lookahead. There is nothing for `SetTextBuf` to
configure, so it cannot be given its FPC meaning without first building
buffered Text I/O. Per this ticket's own instruction I filed
**`decide-settextbuf-needs-buffered-text-io-or-stays-missing`** [U, p55] rather
than stubbing: recommendation is leave it missing now, and file buffered Text
I/O as its own Track B ticket ranked on the *performance* case (a syscall per
character is the real cost), not on this signature.

### Test

`test/lib_text_seek_rename.pas`, wired into `make lib-test`, 27 seek rows plus
the loop and rename cases, sentinel `TEXTSEEK OK` on the last line.

Every row records **the cursor as well as the Boolean** — a test that only
checked the answer would pass an implementation that ate the token. The
motivating case from this ticket is asserted directly: the `SeekEof` sum loop
over `' 10 20\n30 \n'` gives 60 in three turns, and the same loop written with
`Eof` is asserted to take **one extra empty turn** — the defect the pair exists
to remove, pinned rather than described.

`#1`, `#31` and `#33` are in the table specifically as the boundary. **Negative
control run:** replacing the predicate with `c <= 32` fails the test with 9
errors, on exactly those rows plus the `SeekEoln` terminator cases. A test that
passes on the first run has not yet been shown to be able to fail.

## Log
- 2026-08-28 — resolved, commit fa667c98a.
