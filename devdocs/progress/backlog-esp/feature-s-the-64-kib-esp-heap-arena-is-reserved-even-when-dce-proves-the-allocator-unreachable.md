---
prio: 60
track: S
type: feature
status: backlog
found: 2026-09-21
found-by: frankB
owner: ""
blocked-by: ["bug-s-three-different-pxxdynsetlen-bodies-are-visible-at-once-on-every-esp-isa"]
summary: "EspArena is 65,536 B of unconditional BSS under {$ifdef PXX_ESP} -- 97.1% of an EMPTY bare program's 67,464 B of SRAM, and ~23% of a 276,832 B free DRAM pool (THAT DENOMINATOR IS NOT MINE -- reported by frankz-e5 as the figure after f028632c3 removed the dead 64 KiB NilPy arena; I did not measure it, so the percentage is only as good as it is) -- and it is reserved even when DCE has PROVED that nothing can reach it. This is SRAM, the resource the owner ruled relevant on 2026-09-20 ('SRAM here is most relevant, ESP's have plenty flash memory so that's a lesser issue'), and it is the SECOND unconditional BSS reservation in four days to be the largest single SRAM item -- bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss was 32,768 B and was fixed on 2026-09-18 by reserving iff a handler can exist. THE SAME ONE-LINE PREDICATE APPLIES AND IS NOW DECIDABLE, which is the point of filing it: measured 2026-09-21 on a de-duplicated build, an empty bare program drops EVERY allocator entry point -- PXXAlloc, PXXRealloc, PXXStrAllocSize, PXXObjAlloc, PXXObjAllocRaw, PXXObjAllocRaw2 all report `<- DROPPED` under --dce-why -- leaving live bodies 2 (150 B) and code 848 B, while bss stays 66,808 B. An arena with no surviving reader is reserved anyway. BLOCKED-BY the PXXDynSetLen collision, and that ordering is load-bearing rather than bookkeeping: while the orphan exists it roots PXXAlloc unconditionally, so the predicate can never come out false and a guard written on it would be untestable. The expected win is bounded and honest -- it is 64 KiB for programs that do not allocate, and most real programs do; the case for it is the same as the alt stack's, that a facility the program cannot use should not cost a quarter of the chip's RAM."
---

# The 64 KiB ESP heap arena is reserved even when DCE proves the allocator unreachable

## Measured

`compiler/builtin/builtinheap.pas:1155`, inside `{$ifdef PXX_ESP}`:

    EspArena     : array[0..(HEAP_ARENA div 8) - 1] of Int64;

with `HEAP_ARENA = 65536` by default. Unconditional for every ESP program.

An **empty** bare program, on a de-duplicated build (see the blocker):

    dce: bodies 84  live 2 (150B)  dead 81 (70422B)
    dce: code 71144B -> 848B
    dce-why:  [match] 3198B  PXXAlloc        <- DROPPED
    dce-why:  [match] 1137B  PXXRealloc      <- DROPPED
    dce-why:  [match]  314B  PXXStrAllocSize <- DROPPED
    dce-why:  [match]  525B  PXXObjAlloc     <- DROPPED
    dce-why:  [match]  525B  PXXObjAllocRaw  <- DROPPED
    dce-why:  [match]  525B  PXXObjAllocRaw2 <- DROPPED
    ok: [code=848B  data=656B  bss=66808B]

**Code falls to 848 B and BSS stays at 66,808 B.** Every entry point to the heap
is gone and the heap is still reserved.

Proportions, so the number is not quoted without its denominator: 65,536 of an
empty program's 67,464 B of `data + bss` is **97.1%**, and against a **276,832 B** free DRAM pool it is **23.7%**.

**The denominator is borrowed, and marked as such**: 276,832 B comes from
frankz-e5 (the pool after `f028632c3` removed the dead 64 KiB NilPy arena). I
have measured the 65,536 and the 67,464 myself; I have NOT measured the pool.
Re-derive it before quoting the percentage anywhere it matters -- a ratio is two
claims and only one of them is mine.

## Why this is the right resource

Owner, 2026-09-20: *"SRAM here is most relevant, ESP's have 'plenty' flash
memory so that's a lesser issue."* Image-size wins are the lesser axis; this one
is SRAM.

## The precedent, four days old

`bug-a-the-signal-alt-stack-is-32768-bytes-of-unconditional-bss` was the same
shape at half the size: 32,768 B of BSS reserved whether or not a handler could
exist. `16ebf18ce` fixed it by splitting the reservation into
`EnsureSignalAltStack` and calling it only under the predicate the emitter
already used — *reserved iff emitted*, one place, so a new backend cannot forget.

That pattern transfers directly. (Note its one sharp edge, paid for on the same
day: a prologue-time READER of a slot whose allocator moved later got silently
nothing — see `12d6c86f0`. Whatever predicate is chosen here must be evaluated
where the arena is *declared*, not where it is first read.)

## Why the blocker ordering is load-bearing

While the `PXXDynSetLen` orphan exists it roots `PXXAlloc` unconditionally, so
"is the allocator reachable" **can never answer false**. A guard written against
that predicate today would pass on every program and could not be shown to fail
— a guard that cannot fail. De-duplicate first; the predicate becomes decidable
and testable in the same step.

## Honest bound on the win

This is 64 KiB for programs that **do not allocate**, and most real programs do.
It is not a claim that every ESP image shrinks by a quarter of the chip's RAM.
The argument is the alt stack's: a facility the program provably cannot reach
should not cost ~23% of free DRAM (subject to that borrowed denominator), and the floor matters for the smallest
targets and for how much headroom a demo has.

A larger, separate question this does not address: whether `HEAP_ARENA` should
be *sized* per program rather than being one 64 KiB constant. That is design and
belongs under the umbrella, not here.
