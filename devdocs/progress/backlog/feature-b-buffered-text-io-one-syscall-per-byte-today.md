---
track: B
prio: 58
type: feature
blocked-by: []
summary: "lib/rtl/textfile.pas issues one PalRead syscall PER BYTE — TFNextByte reads a single byte, with a one-byte pushback slot on top for lookahead. Every Text-based reader in the tree pays a syscall per character. Buffering is the fix; SetTextBuf becoming implementable is a side effect, not the reason."
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
