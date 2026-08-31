---
track: U
prio: 55
type: decide
blocked-by: []
summary: "RULED 2026-08-31 (owner): option (a) — implement it. The ticket's premise is STALE: lib/rtl/textfile.pas already buffers reads at 4096 bytes inline in the Text record, so the job is not 'build buffering', it is one shape change (inline array -> BufPtr/BufSize) after which SetTextBuf is FPC's literal four assignments. Ruled with it: buffer writes too, but take C99 7.19.3p7's buffering POLICY rather than FPC's, order cross-RTL writes with a flush registry, and make lib/crtl's setvbuf real (it is a stub returning success today). Implementation: feature-b-buffered-text-io-and-settextbuf and feature-c-crtl-stdio-buffering-and-setvbuf."
---

# `SetTextBuf`: build buffered Text I/O, or leave it missing?

Filed 2026-08-28 by frankB (Track B) while closing
`feature-b-text-file-surface-seekeof-rename-settextbuf`. That ticket delivered
`SeekEof`, `SeekEoln` and `Rename`, and said of the fourth routine:

> a stub that accepts and ignores the buffer is a silent lie about lifetime, so
> either implement it or leave it missing — a compile error is more honest than
> a routine that pretends. That is a genuine fork, so if the taker disagrees
> with implementing it, file a Track U `decide-*` rather than stubbing it.

I do disagree with implementing it *now*, so here it is. **Stubbing is not on
the ballot** — that call is already made and I am not reopening it.

## Why it is not a small addition

`lib/rtl/textfile.pas` has **no buffering whatsoever**. `TFNextByte` issues one
`PalRead(f.Handle, @one[0], 1)` per byte, with a one-byte pushback slot
(`f.Peek`/`f.HasPeek`) on top for lookahead. There is no buffer for
`SetTextBuf` to replace, so the routine cannot be given its FPC meaning without
first building the thing it configures.

## The fork

**(a) Build buffered Text I/O, then `SetTextBuf` configures it.** This is a
real win independent of the routine: today every character read costs a
syscall, so any `Text`-based reader is one to two orders of magnitude off what
it should be, and the ladder/corpus work reads a lot of text. It is also
genuinely risky in the places that are easy to get wrong — the interaction with
the peek slot, `Eof`'s lookahead, `Flush`, and above all the **fd position
after `Close`**, since a buffered reader that has read ahead leaves the
descriptor somewhere the caller does not expect. That is its own Track B
ticket, not a line in this one.

**(b) Leave `SetTextBuf` missing.** `undefined variable (SetTextBuf)` at compile
time is honest and cheap to act on. Cost: FPC code that calls it — commonly one
line near a `Reset` in file-heavy programs — does not compile, and the fix is
to delete the call, which is safe precisely because we are unbuffered.

## Recommendation

**(b) now, (a) as its own ticket ranked on the performance case, not on
`SetTextBuf`.** The routine is the least valuable reason to build buffering,
and letting it drive the design would produce buffering shaped to satisfy a
signature rather than to make reads fast. When (a) lands, `SetTextBuf` becomes
a few honest lines and can be added then.

Worth noting the compat table in `CLAUDE.md` puts a bare "FPC accepts a form we
reject" at *ranked by how much real code uses it*, and `SetTextBuf` is rare in
real Pascal — it is a tuning knob, not a construct programs are built on. That
is the argument for (b) being cheap, not an argument that (a) is unimportant.

## What I need decided

Only whether (b) is acceptable as the standing answer. If yes, this closes and
I file the buffered-Text-I/O ticket under Track B with a performance
justification. If the preference is (a) first, `SetTextBuf` stays missing in the
meantime either way — the two differ in what gets *scheduled*, not in what the
surface looks like tomorrow.

---

## RULED 2026-08-31 (owner) — option (a), implement it

Ruled after measuring FPC directly rather than reasoning about it. **The
measurements are the ruling's evidence and are recorded here in full, because
every one of them moved the answer.**

### The ticket's own premise was stale

This ticket says `lib/rtl/textfile.pas` "has no buffering at all — it reads one
byte per `PalRead` syscall". That has not been true for some time. The `Text`
record already carries a 4096-byte read buffer, inline:

```pascal
Text = record
  Handle: Integer; Name: AnsiString; HitEof: Boolean;
  Buffered: Boolean; BufPos: Integer; BufLen: Integer;
  Buf: array[0..TF_BUFSIZE - 1] of Byte;    { TF_BUFSIZE = 4096 }
end;
```

So the fork as filed — "build buffered Text I/O, or leave `SetTextBuf` missing"
— was resting on a cost that no longer exists. **This is why the ruling is (a)
and not (b): frankB's recommendation of (b) was correct against the tree he
measured, and wrong against the tree we have.** Nobody misjudged; the file moved
under the ticket. (*The name is not the thing* — a ticket's stated premise is
evidence about the tree at filing time and nothing else.)

### What FPC actually does — measured, fpc 3.2.2, 8893-byte file, 2000 lines

`SetTextBuf` is not a hint. The syscall count moves exactly with the size:

| `SetTextBuf` size | `read()` syscalls |
| --- | --- |
| (none — FPC default 256) | 36 |
| 16 | 557 |
| 128 | 71 |
| 4096 | 4 |

And the implementation is four assignments, no copy and no seek:

```pascal
Procedure SetTextBuf(Var F : Text; Var Buf; Size : SizeInt);
Begin
  TextRec(f).BufPtr:=@Buf;  TextRec(f).BufSize:=Size;
  TextRec(f).BufPos:=0;     TextRec(f).BufEnd:=0;
End;
```

Three observable consequences, all measured, all of which we inherit if we copy
FPC — and the owner's reason for wanting the example was precisely that
*"caching/buffering has side effects and only the programmer knows what is right
here"*:

1. **Read-ahead moves the fd.** After `ReadLn` returned the 2-byte line `"1"`
   with a 64-byte buffer, `fpLSeek(handle, 0, SEEK_CUR)` reported **64**. Any
   code touching the raw descriptor — `dup`, handing the fd to a child, mixing
   `Text` with untyped-file calls — sees a position ahead by up to one buffer.
2. **Mid-stream `SetTextBuf` silently loses data.** Calling it after `Reset` is
   accepted; the next `ReadLn` returned `"9"` where `"2"` was due. The four-line
   implementation above is the whole explanation: pointer swapped, indices
   zeroed, pending bytes dropped, no seek-back.
3. **Buffer lifetime is the caller's.** `Buf` is by-reference and retained. A
   local array going out of scope while the file is open leaves the RTL writing
   into a dead frame. FPC neither copies nor tracks it.

### The write side: adopt buffering, but NOT FPC's policy

FPC buffers `Output` *and* `ErrOutput` and flushes both at exit. Measured with
both streams into one pipe — the program wrote `STDERR-MARKER` second-to-last
and the pipe received it **last**, after `clean exit`:

```
line 1 … line 5
clean exit
STDERR-MARKER
```

Relative ordering of stdout and stderr is destroyed whenever stdout is not a
terminal. That is a real defect for anything a tool reads, and it is FPC's, not
an inherent cost of buffering.

**The crash case is NOT a cost** — worth recording because it is the objection
everyone raises first. FPC's runtime-error path flushes on the way out: the
segfault run exited 216 and the output file still held all five lines. Only a
hard signal loses buffered output, which is true of every buffered runtime.

So: **take C99 §7.19.3p7's policy instead** — stderr not fully buffered, stdout
line-buffered when it refers to an interactive device, fully buffered otherwise.
That is the rule FPC ignores, it is the rule our own `lib/crtl` must follow to
conform anyway, and adopting it makes the stdout/stderr interleaving above
simply not happen.

### Cross-RTL ordering — a flush registry, not mutual calls

Today there is **no ordering bug**, because both sides are unbuffered:
`lib/crtl/src/stdio.c`'s `fputc` is one `write()` syscall per character. The
hazard is one we would be *introducing*, and it is one FPC never had to answer
because it only ever had a single frontend. We have five plus `lib/crtl`, and
two independent buffers on one descriptor reorder output *within a single
program*.

Owner's call, and it is the right one: **check whether the other buffer is
dirty and flush it first.** Implement it as a **registry**, not as mutual
references — each RTL registers a flusher for a destination; before writing into
its own buffer, it flushes any other registered dirty buffer for that
destination. O(N) in live streams, no RTL names another, collapses to a null
check when only one is linked. Mutual calls would couple `lib/rtl` and
`lib/crtl` in both directions and pull crtl into programs that never asked for
it.

With the C policy above in place, the registry only ever has to handle the
**same-fd** case. The different-fd case (two descriptors onto one terminal) would
require `fstat` and comparing `st_dev`/`st_ino`, and the C policy removes the
need for it.

### It also settles a question already answered the wrong way

`lib/crtl/src/stdio.c:1051`:

```c
int setvbuf(FILE *stream, char *buf, int mode, size_t size) { (void)stream; (void)buf; (void)mode; (void)size; return 0; }
```

A stub that accepts a caller-supplied buffer, ignores it, and returns
**success** — the exact shape this ticket exists to reject, sitting in the C
frontend with the opposite answer, and the more dangerous one because C callers
check the return. It is fixed by the same work: real buffering makes `setvbuf`
real.

### What lands

Two tickets, because the halves are in different lanes and the C half stands on
its own merits (a syscall per character is worth fixing regardless of
`SetTextBuf`):

- **`feature-b-buffered-text-io-and-settextbuf`** (Track B) — inline `Buf` array
  becomes `BufPtr`/`BufSize` with a default inline buffer pointed at, so the
  common case still allocates nothing; `SetTextBuf` as FPC's four assignments;
  write-side buffering under the C policy; the existing non-seekable guard
  (`f.Buffered := ... PalSeek(...) >= 0`) **kept as the default but overridable
  by an explicit `SetTextBuf`**, since a caller naming a buffer is a different
  signal from us choosing to buffer.
- **`feature-c-crtl-stdio-buffering-and-setvbuf`** (Track C) — buffered `FILE`
  writes under the same C policy, real `setvbuf`, and the shared flush registry.

**Reproductions for every number above** are in this session's scratchpad shape
and are three short programs; they are cheap to rebuild and are described
precisely enough here to redo from the text alone.
