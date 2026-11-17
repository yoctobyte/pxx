---
track: ESP
tags: [xtensa, windowed, prologue, codegen, gibux, performance]
prio: 5
type: bug
blocked-by: []
summary: "Every windowed xtensa procedure began `entry a1, 32; mov.n a15, a1; l32r a8, F; sub a8, a1, a8; movsp a1, a8`. A MOVSP right after ENTRY always finds the caller's window live, so it raises an AllocaCause exception on every call. ESP-IDF and Linux handle it with a spill-and-retry trap per call; Gibux had no handler and stopped BusyBox at its first call. PatchProcPrologue now puts the whole frame in ENTRY's immediate when 32+F <= 32760 (`entry a1, 32+F; ...; add a15, a1, a8; nop`), with the same final sp, the same a15 and the same layout, which is gcc's shape. The init thunk's prologue (560ac6add9) also uses one ENTRY now. Real alloca/VLA and frames over 32 KB keep MOVSP."
status: done
owner: unassigned
---

# The windowed prologue's MOVSP trapped on every call

pxx2 found it running BusyBox on Gibux: "exception 5 (alloca)" at `entry a1, 32 / mov.n a15, a1 / addi a8, a1, -128 / movsp a1, a8`, which is the .init_array thunk's prologue. The ordinary procedure prologue has the same MOVSP: the BusyBox text had 7124 of them.

## Fix
- **PatchProcPrologue (windowed arm).** Once the frame size F is known, and only when 32+F fits ENTRY's imm12*8 and the bytes are exactly the shape EmitXtensaFrameReserve emitted:
  - ENTRY's immediate becomes 32+F;
  - `sub a8,a1,a8` becomes `add a15,a1,a8`, so a15 is still the 32-byte frame's sp, which the locals and the a7 bias are addressed from;
  - MOVSP becomes NOP.
  The frame-size literal stays, because a8 = F feeds the add.
- **The init thunk prologue.** `entry a1, 160` with a15 = sp + 128.

The overflow-argument call sites (more than 6 + outgoing-area words) and alloca still use MOVSP. That is legal and is how gcc does it; there it only traps when the caller's window is live.

## Test
The xtensa suite runs every windowed program through the new prologue under qemu: setjmp/longjmp, exceptions, coroutines, deep recursion and C objects. The object checks (shared runtime, posix main, PIE, setjmp, vfork, heap arenas) pass. qemu-xtensa does not raise AllocaCause, so the trap itself shows only on Gibux and on silicon. pxx2 verifies there.
