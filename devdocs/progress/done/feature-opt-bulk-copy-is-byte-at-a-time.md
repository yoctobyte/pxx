---
track: O
prio: 65
type: feature
summary: "DONE 2026-08-29. Eight byte loops in five routines became PXXBlockCopy/PXXMemZero calls: SetLength 3.0x and Copy() 1.9x on aarch64, 1.4x arm32, and EXACTLY ZERO on x86-64 -- which open-codes all of it (inline rep stosb, __pxxblockmove), so this ticket benchmarked the one target the work cannot help and priced itself from that. The old 23x is 3.6x at HEAD and 77% of what remains is the ALLOCATOR, not any copy -- successor is an allocator ticket. Two method traps banked: a pinned-vs-HEAD compiler A/B does not test an RTL change (both read builtinheap from the working tree), and the correctness test PASSES on x86-64 with PXXBlockCopy's byte tail deleted while giving 415 failures on aarch64. Filed on the way: bug-a-for-loop-limit-is-evaluated-after-the-control-variable-is-assigned."
status: done
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

---

## RESOLVED 2026-08-29 — done, but almost nothing about this ticket was still true

Re-measured at HEAD before touching anything, per the note above. The headline,
the cause, the site list, the fix shape and the target were each wrong in a
different way. Recording all five, because the pattern is more useful than the
patch.

### 1. The 23x is now 3.6x, and the landed work did that

`Copy(a)` on a 64-element array, 3M iterations, **binary `061099b514c0`**,
FPC 3.2.2, both sides alternated in one window on a contended box:

| | time | vs FPC |
| --- | --- | --- |
| FPC | 0.25 s | 1.0x |
| pxx | 0.91 s | **3.6x** |

The ticket's 23x described a compiler that no longer exists —
`PXXBlockCopy` and the `__pxxblockmove` intrinsic closed most of it. Nobody
re-measured, so the ticket kept advertising 23x at prio 65 for three weeks.

### 2. The benchmark was wrong twice before it was right, and the second one is the interesting one

- `k: Integer` — **FPC's default `Integer` is 16 bits**, so `3000000` did not fit
  and it would not compile. Obvious, caught by the compiler.
- Fixed by making the array `array of Integer` -> and **FPC's element was then 2
  bytes while pxx's was 4**. The benchmark compiled, ran, and printed *the same
  sum on both sides* — because the values were small enough not to differ. **The
  two programs were copying 128 and 256 bytes and agreeing anyway.** Caught only
  because a second benchmark with larger values disagreed (`105884512` vs
  `4500001500000`).

  A cross-compiler benchmark whose two sides agree on the answer can still be
  measuring different amounts of work. Agreement on the OUTPUT is not agreement
  on the WORKLOAD. `array of LongInt` on both sides is the fix.

### 3. The remaining gap is the allocator, not any copy

Same 3M iterations with the copy removed and only the allocate/zero/free churn
left:

| | Copy() | alloc-only |
| --- | --- | --- |
| FPC | 0.25 s | 0.29 s |
| pxx | 0.91 s | **0.70 s** |

**77% of pxx's `Copy()` time is allocation.** The copy itself is ~0.21s against
FPC's ~0. The ticket's *first* hypothesis (allocation) was retracted in favour of
the byte loop; the retraction was right for the 23x and is wrong for what is left
today. Successor work is an allocator ticket, not a copy ticket.

### 4. The site list was short, and the fix landed anyway

Eight open-coded byte loops in five routines, not "at least four more places":
`PXXDynSetLen` (hosted **and** ESP-lean, zero-fill and carry-over),
`PXXDynArrayUnique`, **`PXXStrSetLen`** — missed entirely by the original list
and on every target — and the cstring→managed-string payload copy. Each is now
one call to `PXXBlockCopy` or `PXXMemZero`. Several of the loops recomputed
`newLen * elSize` **in their own loop condition**, so every byte cost a multiply
too.

### 5. The target was wrong — and this is the finding that matters

| measurement (isolated) | before | after | |
| --- | --- | --- | --- |
| `SetLength(a,64)` x300k, aarch64 | 5.50 s | 1.80 s | **3.0x** |
| `Copy(a)` x200k, aarch64 | 6.60 s | 3.50 s | **1.9x** |
| `Copy(a)` x200k, arm32 | 9.10 s | 6.40 s | **1.4x** |
| everything, x86-64 | — | — | **no change** |

x86-64 open-codes all of it: `IR_SETLEN_DYN` is inline `rep stosb` and
`PXXMemCopy` is `__pxxblockmove`. So **this ticket measured the one target the
work cannot help, and priced itself from that number.** The win is 1.4-3.0x on
the other four hosted targets and exactly zero on the one it benchmarked.

## Two method traps, both caught, both worth more than the patch

### A `pinned` vs `HEAD` comparison does not A/B an RTL change

`builtinheap.pas` is read from `PXX_HOME` **at compile time**, so two different
compiler binaries still use the **working tree's** copy of it. My first aarch64
A/B read 1.74 vs 1.76 — a flat line produced by measuring the same RTL twice.
Isolating properly (one compiler binary, two RTL sources) turned that into
5.50 vs 1.80. **A compiler-binary A/B silently tests nothing when the change is
in a runtime source the compiler reads.**

### The correctness test is nearly vacuous on x86-64

`test_bulk_copy_tails` covers every length 0..17 across string `SetLength`,
dyn-array `SetLength`, `Copy()` at every offset and count, aliasing-vs-`Copy`,
and concat, all diffed against FPC 3.2.2. Then it was checked the only way a
test's value can be checked: **`PXXBlockCopy`'s byte tail was deleted outright**
— precisely the failure a word loop invites — and

- on **x86-64** the test still **PASSED**
- under `--target=aarch64` the same break gave **415 failures**

For the same reason as the perf result: x86-64 barely executes these routines. A
green natively is close to no evidence here, and the note is in the Makefile
beside the recipe so a future reader does not draw the wrong conclusion from it.
Green on x86_64/i386/aarch64/arm32/riscv32 with the tail intact.

## Found while doing it — filed, not fixed

- [[bug-a-for-loop-limit-is-evaluated-after-the-control-variable-is-assigned]]
  **(A, p70).** The correctness test **segfaulted**, and it was the compiler:
  `for n := 1 to n do` runs 1 iteration where FPC runs 5, `to n - 1` runs 0 where
  FPC runs 4, `downto` is wrong the same way. `ir.inc`'s `AN_FOR` arm stores the
  control variable *before* lowering the limit. Root cause located, including why
  it is not a two-line reorder. The idiom is not contrived — it arrives from a
  computed bound reusing a scratch variable, which is exactly how it arrived
  here.
- **`PXXMemMove` is forward-only on every target** (recorded in the earlier
  re-pricing section above, unchanged). Latent: no current caller overlaps.

## Not done

The allocator (item 3) — that is the remaining 3.6x and it wants its own ticket
and its own benchmark. Alignment handling (the ticket's step 3) was never
measured and is now moot: `PXXBlockCopy` already carries the alignment guard.

## Log
- 2026-08-29 — resolved, commit d42be856b.
