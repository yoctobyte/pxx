---
track: B
prio: 58
type: feature
blocked-by: []
summary: "lib/rtl/textfile.pas issues one PalRead syscall PER BYTE — TFNextByte reads a single byte, with a one-byte pushback slot on top for lookahead. Every Text-based reader in the tree pays a syscall per character. Buffering is the fix; SetTextBuf becoming implementable is a side effect, not the reason."
status: done
owner: frankB
---

# Buffered Text I/O — today it is one syscall per byte

Filed 2026-08-28 by frankB (Track B) out of
`feature-b-text-file-surface-seekeof-rename-settextbuf`, and deliberately filed
**separately from** the `SetTextBuf` question
([[decide-settextbuf-needs-buffered-text-io-or-stays-missing]]) so the fork
there stays clean: this is worth doing on its own, and a design shaped to
satisfy a rarely-used signature would be the wrong design.

## The measurement is in the source

`lib/rtl/textfile.pas`, `TFNextByte`:

```pascal
n := PalRead(f.Handle, @one[0], 1);
```

One byte, one syscall. On top of it sits a **one-byte** pushback slot
(`f.Peek` / `f.HasPeek`) used for lookahead by `Eof`, `Eoln`, `SeekEof`,
`SeekEoln` and the numeric tokeniser. That slot is a correctness mechanism, not
a buffer — it holds exactly one byte and only ever a byte just handed out.

So every `Text` reader in the tree — `TextReadLn`, `TextReadChar`,
`TextReadNumTok`, `TextReadStrTo`, and the seek pair — costs a syscall per
character. A 100 KB file read line by line is ~100,000 `read(2)` calls.

## Why it is not just "add a buffer"

The parts that are easy to get wrong, and the reason this is its own ticket
rather than a line in another:

- **The peek slot must not become a second buffer.** Two lookahead mechanisms
  for one concept is exactly the `normalise-dont-special-case.md` smell; the
  slot should collapse into the buffer's cursor, not sit in front of it.
- **`Eof` currently performs the lookahead itself** and parks the byte in
  `f.Peek`. With a buffer, `Eof` becomes "cursor at end and refill returned
  zero", which changes when the read actually happens.
- **The fd position after `Close` is the trap.** A buffered reader that has read
  ahead leaves the descriptor past what the caller consumed. Anything sharing
  or inheriting that fd — and `Input`/`Output` are shared by construction —
  sees a position the caller never asked for.
- **`Flush` and the write side** have the mirror-image problem, and mixing
  buffered writes with the existing unbuffered path is where a half-migration
  would silently corrupt output.
- **`Input`/`Output` are interactive.** A buffered stdin that reads ahead past a
  newline breaks any program that expects to consume exactly one line, so line
  buffering (or none) has to be selectable per handle — which is, incidentally,
  what makes `SetTextBuf` meaningful.

## Scope

Track B (`lib/rtl/textfile.pas`). Build with `$(PXX_STABLE)`, never rebuild the
compiler. No compiler change expected. Land it incrementally and green — the
read side first, behind the existing entry points so callers do not change,
then the write side.

`SetTextBuf` is **out of scope here** and stays missing until
`decide-settextbuf-needs-buffered-text-io-or-stays-missing` is answered; if the
answer is "add it", it becomes a few honest lines on top of this.

## Gate

`make lib-test` green — it already exercises the Text surface heavily
(`lib_textfile`, `lib_textreadchar`, `lib_textreadnumtok`,
`lib_text_seek_rename`), and those tests assert **cursor position**, not just
values, which is precisely the property a buffering change threatens. Worth a
before/after timing on a large file in the ticket write-up, since the
justification is performance and an unmeasured speedup is not one.

## 2026-08-28 (frankB) — RESOLVED. 1,088,892 read(2) calls become 268.

### Measured, because the justification was performance and an unmeasured speedup is not one

Same program (read a 1,088,890-byte file line by line, count lines and
characters), built against `lib/rtl` before and after, on `pinned` v389:

| | `read(2)` calls | wall (best of 3) | output |
| --- | ---: | ---: | --- |
| before | **1,088,892** | 1.56 s | `lines=20000 chars=1068890` |
| after | **268** | 0.30 s | `lines=20000 chars=1068890` |

1,088,892 calls for 1,088,890 bytes is the ticket's claim confirmed on the
nose: one syscall per byte, plus two. **4063x fewer calls, 5.2x faster wall**,
byte-identical answer.

### The peek slot is gone, not joined

`f.HasPeek` / `f.Peek` are removed from the record; `grep HasPeek lib/` returns
nothing. Pushback is now `Dec(f.BufPos)` — the byte a caller may push back is
the one `TFNextByte` just handed over, and it is still sitting at `BufPos-1`, so
there is nothing to store and nothing to keep in sync.

This was the part worth doing carefully rather than the buffer itself. Adding a
buffer *underneath* the slot would have left two lookahead mechanisms for one
concept — the `normalise-dont-special-case.md` smell, and a much better example
of it than the `TFIsSpace` case I refused to merge earlier today, because these
two really are one concept. The whole change is a single asserted transaction
for the same reason: half-applying it is precisely how you end up with the bug
it removes.

`TextReadLn` keeps its own loop, and still for its original reason — it must not
set `LastIOResult` on success, or it clears a stale code a `{$I+}` region's
`PXXIoCheck` can still see. That distinction now lives in `TFFillEx`'s `quiet`
flag instead of a duplicated read: same contract, one mechanism.

### The fd position after Close — the trap named in the filing, and closed

Read-ahead leaves the descriptor past what the caller consumed, so anything
inheriting or sharing the fd starts somewhere nobody asked for. `Close` rewinds
by whatever is still buffered. Verified at the syscall level rather than by
reading the code — a program that reads one 50-character line and closes:

```
lseek(3, 0, SEEK_CUR)   = 0        <- TFOpened's seekability probe
read(3, "line 0 with some payload"..., 4096) = 4096
lseek(3, -4045, SEEK_CUR) = 51     <- the rewind
close(3)                = 0
```

50 characters + the newline = **51 bytes consumed, and the descriptor is left at
51.** Exact, not approximately right.

**Buffering is gated on seekability** (`PalSeek(h, 0, PAL_SEEK_CUR) >= 0`), which
answers two questions with one test: a pipe or terminal cannot be rewound, so
`Close` could not honour the above; and it must not be read ahead on anyway.
No `isatty` needed — the failure of the probe *is* the answer.

**`Input` and `Output` are never buffered**, even when stdin is a redirected
regular file that would pass the probe. There is no `Close` on stdin at which to
rewind, and a program that reads a line then execs a child sharing fd 0 would
hand it a position it never asked for. So the interactive path keeps exactly
today's one-byte reads: this change buys file I/O and deliberately does not
touch the case where read-ahead is observable. That is also the honest limit of
the numbers above — they are file-read numbers.

### Gate

`make lib-test` **REAL EXIT=0** (redirected, not piped — see
`gating-and-waiting.md`), sentinel `lib-test ok (...)` present. The four
Text-surface suites that assert *cursor position* rather than values —
`lib_textfile`, `lib_textreadchar`, `lib_textreadnumtok`, `lib_text_seek_rename`
— all pass, which is the property a buffering change actually threatens.

**Caveat, same as this morning:** the three synapse jobs SKIPPED, because
`external/synapse` is held aside on this box under
`bug-a-a-deep-unit-dependency-parses-with-a-spliced-token-stream`. This run says
nothing about them.

### Left undone, deliberately

The **write** side is still unbuffered — `Flush` remains a no-op and `TextWrite`
goes straight to the fd. Mixing buffered writes into the same handle is where a
half-migration silently corrupts output, and the read side is where the syscall
cost was. `SetTextBuf` stays missing pending
`decide-settextbuf-needs-buffered-text-io-or-stays-missing`; with this in place
it becomes a few honest lines if the answer is yes.

## Log
- 2026-08-28 — resolved, commit PENDING-COMMIT.
