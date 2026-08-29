---
track: U
prio: 55
type: decide
blocked-by: []
summary: "SetTextBuf's contract is 'use this caller-supplied buffer for this handle', and lib/rtl/textfile.pas has no buffering at all — it reads one byte per PalRead syscall. So the fork is: build buffered Text I/O (a real win beyond this routine) and make SetTextBuf mean something, or leave it missing so the compile error stays honest. Stubbing it is already ruled out."
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
