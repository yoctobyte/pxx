---
track: O
prio: 65
type: feature
summary: "STALE HEADLINE -- re-priced 2026-08-29 at 1fd403b28: BOTH proposed fixes already landed (PXXBlockCopy word loop; the __pxxblockmove/rep-movsb intrinsic, 0f6a04644 + 2b85f8c8f), so the 23x and the 3.3x describe a compiler that no longer exists and must not be re-quoted. What remains is 8 open-coded byte loops in 5 routines (the ticket said 4 sites and missed PXXStrSetLen, the hottest), each now a one-line call to the already-landed PXXBlockCopy/PXXMemZero. Re-measure Copy() vs FPC before trusting prio 65. Also recorded: PXXMemMove is forward-only on every target and corrupts overlapping dst>src -- latent, no caller reaches it."
status: working
owner: frank-optimize
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

---

## RE-PRICED 2026-08-29 at HEAD (`1fd403b28`) — fix shapes 1 AND 2 ARE ALREADY LANDED

Opened at HEAD before starting, per the rule. **The headline is stale.** Both of
the fixes this ticket proposes exist in the tree today:

| ticket says | actually, at HEAD |
| --- | --- |
| 1. word-at-a-time with a byte tail — "prototyped and **reverted**, nothing committed" | **landed** as `PXXBlockCopy` (builtinheap.pas:1454): word loop, byte tail, alignment guard `PXXWordCopyOk` |
| 2. a runtime-length block move lowering to `rep movsb` with `rcx` from a register | **landed** as the `__pxxblockmove` / `__pxxblockfill` intrinsic (`AN_BLOCK_MEM`, defs.inc:606, lowered in ir_codegen.inc:8338) |

Landed by `0f6a04644` (*"feat(A): IR_BLOCK_MEM — rep movsb/stosb with a runtime
byte count"*) and `2b85f8c8f` (*"perf(A): the RTL's bulk memory routines now use
the block instruction"*). `PXXMemCopy` today is `__pxxblockmove` on x86-64 and
`PXXBlockCopy` everywhere else. The byte loop this ticket quotes as its cause is
**gone from the routine it quotes it from.**

So the ticket's own measured table is describing a compiler that no longer
exists, and its 3.3x is an estimate of a change already made. Anyone taking this
at prio 65 on the strength of "23x slower than FPC" would be re-doing committed
work. **The prio is wrong until someone re-measures**, and the 23x should not be
quoted again without a fresh number.

### What genuinely remains — the open-coded sites, and the ticket undercounted them

The ticket says the byte loop "is open-coded in at least four more places". That
list was inherited from wherever someone looked first (the same shape as
`forwardlint` naming only the earliest of eight `LowerCase` sites). The real set
at HEAD, all still one byte per iteration:

| site | line | what | reached by |
| --- | --- | --- | --- |
| `PXXStrSetLen` | 3406, 3417 | carry-over, then zero-fill | `SetLength(s, n)` on a string — **all targets** |
| `PXXDynSetLen` (managed) | 3349, 3361 | zero-fill, then carry-over | `SetLength(arr, n)` — all non-ESP targets |
| `PXXDynArrayUnique` | 3240 | the COW duplicate | every write to a shared dyn array |
| `PXXDynSetLen` (ESP-lean) | 1318, 1329 | zero-fill, carry-over | ESP only |
| cstring -> managed str | 1914 | header + payload copy | C-string ingest |

That is **five routines / eight loops**, not four sites. `PXXStrSetLen` is the
one the old ticket missed entirely and is plausibly the hottest of them: string
`SetLength` is on a path everything touches, and unlike the dyn-array ones it has
no ESP guard.

**These are cheap now precisely because 1 and 2 landed.** Each loop can become a
call to `PXXBlockCopy` or `PXXMemZero`, both already defined ABOVE every one of
these sites in the unit (1454 and 3277), both already word-at-a-time, and
`PXXMemZero` already `rep stosb` on x86-64. No new primitive, no backend work, no
new IR. That is the whole remaining job and it is smaller than the ticket's step
1 was.

### `PXXMemMove` does not do what its name says — flagged, not fixed

Checked because widening it with a word loop was the change most likely to be
silently wrong. It is worse than that: **`PXXMemMove` is forward-only on every
target.** x86-64 calls `__pxxblockmove` (`rep movsb` — forward), everything else
calls `PXXBlockCopy` (an explicitly forward loop). Neither picks a direction from
the operands. For overlapping regions with `dst > src` it corrupts.

Today that is latent rather than live — its callers are the whole-record copy in
the non-x86 backends, the riscv32/xtensa aggregate-result epilogue, and
`ReallocMem` (builtinheap.pas:857, 901), where the destination is a fresh block.
Distinct record variables do not overlap, and `dst = src` is harmless.

It is a **contract hazard, not a current defect**: the name promises overlap
safety the implementation does not provide, and the obvious future caller — a
dyn-array `Insert`/`Delete` done in place instead of via a SetLength'd temp — is
exactly the overlapping shift that would corrupt silently. Recording it rather
than filing it, since no program reaches it today.

**And the self-host gate would not catch it if it went live.** The fixedpoint
exercises the RTL only through the compiler's own usage patterns, which are
non-overlapping throughout. A green self-host proves the compiler's uses survive;
it does not prove the RTL's contract holds. Worth remembering for any RTL change
whose risk is a contract the compiler happens not to exercise.

### Status

Parked back to `backlog` unclaimed, untouched — **not** because it is done, but
because `builtinheap.pas` is held by another agent (frankA, in it as of this
hour). Nothing was edited. Whoever takes it next should start from this section,
not from the table at the top.

**Before doing any of it: re-measure `Copy()` head-to-head against FPC at HEAD.**
The remaining eight loops may or may not still be worth prio 65 now that the two
big ones are gone, and the only honest way to know is a number from a binary
whose sha you name.
