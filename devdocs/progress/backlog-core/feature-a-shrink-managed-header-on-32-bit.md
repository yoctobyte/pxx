---
track: A
prio: 10
type: feature
summary: "On ILP32 the managed-block header wastes 12 of its 24 bytes: three 8-byte slots each carrying a 4-byte value. Packing to 4-byte slots halves it — and the DEADLINE is phase 2, because it caps the meta word at 32 usable bits"
---

# Shrink the managed-block header on 32-bit targets

> **DE-RANKED 25 -> 15 on 2026-08-19: this ticket's deadline has passed, and was MET.**
>
> The entire argument for filing it early was *"if phase 2 spends the upper 32 bits this
> becomes impossible."* Phase 2 (`feature-nilpy-text-string-kind`) is **done and obeyed the
> constraint** — `builtinheap.pas:166` reserves bits 32-63, and line 210 stores the encoding
> **enum** this ticket asked for rather than a codepage. So nothing can make it impossible
> now.
>
> What remains is an optional ESP memory win with no urgency behind it. That is a genuine
> change in how it should rank, in the direction of *lower* — recorded because a ticket
> filed under a deadline keeps its urgency in the reader's mind long after the deadline is
> gone. Found by frank2's feature triage.

- **Type:** feature (memory) — **Track A**
- **Design:** `devdocs/dev/managed-block-header.md`.
- Not urgent. **But its constraint is** — see "the part that is time-critical".

## The waste

`PWord` is a pointer to a **machine word** — 8 bytes on 64-bit, 4 on 32-bit —
while the header's field offsets are fixed 8-byte strides on every target:

```
[meta:8][refcount:8][length:8][data...]      handle = block + 24
```

So on ILP32 each slot carries a 4-byte value in its low half and 4 bytes of
padding: **12 of the 24 header bytes are dead**, on every string, dynamic array
and object. Packing to 4-byte slots gives a 12-byte header (16 with alignment),
roughly halving per-block overhead.

That matters most exactly where memory is scarcest. Under `PXX_ESP` the heap is a
single **64 KiB static arena** (vs a 256 MiB mmap chunk on a host), and xtensa
and riscv32 are both ILP32 — so this is an ESP-capacity feature more than a
desktop one. Frozen `string[N]`/shortstring already sidestep the header entirely
and remain the primary ESP lever.

## The part that is time-critical

Packing makes the **meta word 32 bits wide on ILP32**. Whatever phase 2
(`feature-nilpy-text-string-kind`) puts in bits 32–63 would have nowhere to live
there — so either the layouts diverge per target (bad: the field means different
things on different machines) or the upper half must be permanently unused.

**So the constraint is already recorded in the design doc and phase 2 must obey
it: every meaningful field lives in the low 32 bits.** That is
`BlockKind(8) | Flags(8) | KindData0(8) | KindData1(8)`, with 32–63 reserved.
It also forces `KindData0` to hold a small **encoding enum** rather than a raw
codepage (`CP_UTF8` = 65001 does not fit in 8 bits) — which is the better field
anyway.

If this ticket is never done, nothing is lost. If phase 2 spends the upper 32
bits, this ticket becomes impossible. That asymmetry is the whole reason it is
filed now at a low priority rather than later.

## Sketch

Introduce the stride as a constant (`PXX_HDR_SLOT` = `SizeOf(NativeInt)`) and
derive `PXX_HDR_SIZE`/`_META`/`_RC`/`_LEN` from it, rather than the current fixed
8s. The Pascal side in `builtinheap.pas` already routes everything through those
names since phase 1, so most of it follows. The work is the **x86-64 emitter**
(which hardcodes `[rax-16]`, `[rsi-32]`, `sub rax, 24` and the inline allocation
sequences) — but note x86-64 is LP64 and would not change; it is the 32-bit
backends that would need their own offsets, and today they hardcode almost
nothing because they delegate managed release to the Pascal runtime. Check that
claim before costing the work: it is what made phase 1 much smaller than
expected.

## Gate

Track A, and the same shape as phase 1 — but **not** via FPC. Seed the self-host
from `pinned` (which carries its own frozen RTL); `make compiler/pascal26` seeds
from a binary with no versioned RTL and will silently produce a core-dumping
compiler ([[bug-a-self-host-seed-has-no-versioned-rtl]]). Then
`testmgr --tier full` with the 32-bit targets specifically,
`-dPXX_HEAP_DEBUG` for free-base errors, then `stabilize` + `pin`. An ESP/xtensa
build under `--platform=esp --esp-profile=bare` is the point of the exercise, so
measure the arena headroom before and after.

## Triage 2026-08-19 (Track D re-triage pass, pin v363) — the DEADLINE has passed, and was MET

The ticket's whole argument for being filed early was a deadline: *"If phase 2
spends the upper 32 bits, this ticket becomes impossible."* **Phase 2
(`feature-nilpy-text-string-kind`) is done** — and it obeyed the constraint.
Checked in the implementation rather than in the design doc:

`compiler/builtin/builtinheap.pas:166` — *"BlockKind(8) | Flags(8) |
KindData0(8) | KindData1(8), bits 32-63 RESERVED"* — and line 210 stores a
small **encoding enum** in `KindData0`, exactly as the ticket demanded, *"NOT a
codepage"*.

**So the urgency is gone and only the optional memory win remains.** This is
now a plain ESP-capacity optimization with no expiry, which is a real change in
how it should rank: nothing is lost if it is never done, and nothing can make
it impossible any more. The `PXX_HDR_SLOT` sketch and the seed-from-`pinned`
gate note are unaffected.

**One inconsistency found while checking, for whoever owns
`devdocs/dev/managed-block-header.md`:** its per-kind table still lists
ByteString's `KindData0` as *"codepage (`CP_UTF8`=65001 fits a Word —
FPC-exact)"*, which contradicts both the prose eleven lines above it (an 8-bit
field cannot hold 65001) and the shipped implementation. The prose and the code
agree; the table row is the stale one. Not edited here — `devdocs/dev/**` is
not Track D's ground.
