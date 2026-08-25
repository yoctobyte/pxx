---
track: O
prio: 65
type: feature
summary: "The runtime's bulk-copy primitives move ONE BYTE per iteration. Copy() on a 64-element array is ~23x slower than FPC's (2.54s vs 0.11s over 3M copies). A word-at-a-time loop -- ~10 lines, portable, no backend work -- was prototyped and measured at 3.3x of that back."
---

# The runtime's bulk copy is one byte per iteration

- **Type:** feature — **Track O** (optimization; file-owned by Track A, obeys
  A's gate). Files: `compiler/builtin/builtinheap.pas`.
- **Opened:** 2026-08-07. Originally filed as an open-array-parameter cost item;
  **re-scoped the same day** — see "How the scope changed" below, because the
  first framing pointed at the wrong thing.

## Measured

`Copy(a)` on a 64-element `array of Integer` (256 bytes), 3,000,000 times,
x86-64, `-O2` both sides, identical output, best of three:

| | time | per copy | per byte |
| --- | --- | --- | --- |
| FPC | 0.11 s | ~37 ns | ~0.14 ns |
| pxx | **2.54 s** | ~845 ns | ~3.3 ns |
| pxx, word-loop **prototype** | **0.77 s** | ~257 ns | ~1.0 ns |

~3.3 ns/byte is about 10 cycles per byte — the signature of a byte-at-a-time
loop, not of an allocation.

## Cause

`PXXMemCopy` (`builtinheap.pas`) is:

```pascal
  while i < n do
  begin
    PByte(Int64(dest) + i)^ := PByte(Int64(src) + i)^;
    i := i + 1;
  end;
```

One load, one store, an increment and a compare **per byte**. The same shape is
open-coded in at least four more places in that unit — `PXXDynSetLen`'s grow
path (twice: the zero-fill and the carry-over), `PXXDynArrayUnique`'s duplicate,
and `PXXMemMove`.

The x86-64 backend is **not** the problem and already knows better: `IR_COPY_REC`
emits `rep movsb`. But it can only do that because the byte count is a
compile-time constant (`movabs rcx, <imm>`); the runtime helpers exist precisely
for the cases where the length is dynamic, and they are written in portable
Pascal.

## Who pays

Everything that copies bytes in bulk, which is more than it looks:

- `Copy(arr)` — the user-facing whole-array duplicate.
- dynamic-array `Delete` / `Insert` (they lower to a SetLength'd temp filled via
  these helpers).
- `SetLength` on GROWTH — the carry-over of the old contents, plus the zero-fill
  of the new tail.
- `PXXDynArrayUnique` — the copy-on-write duplicate, which is also what a future
  COW open-array parameter would lean on.
- by-value **open-array parameters**, as of
  [[bug-a-open-array-value-parameter-aliases-instead-of-copying]].

## Fix shape, cheapest first

1. **Word-at-a-time with a byte tail.** Prototyped and measured above:
   **2.54 s → 0.77 s, a 3.3x win** for ~10 lines, portable, no backend work, no
   new IR. Applies to every helper listed above. This is the obvious first step
   and it is most of the available win.
2. **A runtime-length block-move IR op** lowering to `rep movsb` with `rcx` from
   a register rather than an immediate — i.e. what `IR_COPY_REC` already does,
   generalised to a dynamic count. Gets the rest of the gap to FPC on x86-64;
   needs a fallback path per backend.
3. Alignment handling (head/tail) before the word loop, if step 1's measurement
   on unaligned buffers warrants it — **not measured**, and worth measuring
   before writing, since dyn-array data is 8-aligned by construction here.

The prototype was built, measured and **reverted** — nothing of it is committed.
It touched only `PXXMemCopy`; the other four sites would need the same treatment
and were left alone.

## How the scope changed, and why it is recorded

This ticket was first filed as "a by-value open array now copies on every call,
6.4x on a hot path". That framing survived about ten minutes of the user's
attention: *"we are just talking about the copy() function right? the 'const'
distracted me, that's just a cheap optimization."* Correct — `const` merely
dodges the copy, and the open-array parameter is one consumer among several. The
subject is the copy primitive, and once measured directly (`Copy()` head to
head, no parameters involved) the cause turned out to be the byte loop rather
than the heap allocation the first version of this ticket guessed at.

The earlier version's hypothesis — "FPC almost certainly puts the copy on the
stack" — is **retracted**. It was explicitly flagged as unmeasured, and the
measurement says otherwise: a stack-vs-heap difference does not produce 10
cycles per byte, and the word-loop prototype recovers 3.3x without touching
allocation at all. Allocation may still be worth a look afterwards; it is not
the main term.

## Not this ticket

The `const`/no-copy baseline is itself ~5x slower than FPC (0.47 s vs 0.09 s for
192M sum-loop iterations) — ordinary loop-and-index codegen, no copy anywhere in
it, reproduces on `pinned`. Unrelated, and it wants its own ticket and a wider
benchmark than one hand-written loop.

## Gate

A's gate (`make compiler/pascal26` + self-host fixedpoint + `gate.sh quick`) —
these helpers are used by the compiler itself, so self-host is a real test here
rather than a formality. Plus: the `Copy()` benchmark above before/after, the
FPC differential in `test/test_open_array_value_param_copies.pas` staying
byte-identical, and a correctness check on **odd** lengths and small sizes (1..7
bytes) — the byte tail is exactly where a word loop goes wrong.
