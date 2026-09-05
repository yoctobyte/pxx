---
slug: feature-b-getfpcheapstatus-needs-always-on-heap-accounting
title: "GetFPCHeapStatus / TFPCHeapStatus — the LAST open wall on the FPC compiler corpus, and it needs real heap counters rather than a stub"
track: B
prio: 50
type: feature
status: backlog
found: 2026-09-05
found-by: frankB
owner: ""
blocked-by: []
summary: "FPC's System exposes `TFPCHeapStatus` (a record of MaxHeapSize/MaxHeapUsed/CurrHeapSize/CurrHeapUsed/CurrHeapFree) and `GetFPCHeapStatus`. cclasses.pas:676 uses both in its tmemdebug helper, and that is now the ONLY open wall on the FPC compiler-source corpus -- it blocks cclasses, comphook, finput and cfileutl, measured 2026-09-05 with compiler 108f95a7f278 under --mimic-fpc-compiler. The type is trivial; the FUNCTION is not, and that is the whole ticket. Our allocator has NO always-on counters: -dPXX_ALLOC_CENSUS instruments PXXAlloc/PXXFree at COMPILE time, so a released binary carries no heap accounting at all. Returning zeros would make four units compile while the function lies -- a caller printing a memory delta would print 0 with no error -- which is the compiler-appeasement workaround CLAUDE.md refuses. The real work is deciding whether the allocator carries always-on counters and paying that cost per allocation."
---

# Why this is not a ten-minute job

The type is five pointer-sized fields and could be declared in an afternoon.
**`GetFPCHeapStatus` is the ticket**, and the reason is measured:
`-dPXX_ALLOC_CENSUS` is a **compile-time** define that instruments `PXXAlloc` /
`PXXFree` (`ir_codegen.inc:205`). Grepping for an always-on counter finds
nothing. So a shipped binary has no idea how much heap it holds.

Three ways to close it, and the choice is a real one:

1. **Always-on counters** — two integers bumped in `PXXAlloc`/`PXXFree` plus a
   high-water mark. Truthful, and it costs an add per allocation on every
   program whether or not it ever asks. That cost lands on the self-hosted
   compiler's own inner loop.
2. **Counters behind a runtime switch**, off by default, with
   `GetFPCHeapStatus` returning zeros AND a way for the caller to know the
   numbers are unavailable. Truthful-with-a-hole, and FPC itself reports
   partial data on some targets, so it has precedent.
3. **Arena-derived numbers.** The allocator already knows its arena count and
   bump pointer (the census line prints `arenas=1 bump=21`). `CurrHeapSize` and
   `CurrHeapFree` may be answerable from arena bookkeeping that ALREADY EXISTS,
   with only `CurrHeapUsed`'s live-bytes figure needing a counter. Cheapest if
   it holds — **measure this before choosing 1.**

**Do NOT close it by returning zeros.** The consumer is
`cclasses.pas`'s `tmemdebug.start`/`.stop`, which prints a memory delta: zeros
make it print `0` forever, with no error and no tell. That is a silent wrong
value bought to make a corpus advance, and it is the exact shape of
CLAUDE.md's "no compiler-appeasement workarounds" — the corpus is a measuring
instrument, not a dependency, so a unit that does not compile is INFORMATION and
a unit that compiles around a lie is not.

# Gate

Whatever B's gate is, plus: a program that allocates a known amount, calls
`GetFPCHeapStatus`, frees, and calls it again, asserting the numbers MOVE in the
right direction. A test asserting only that the call compiles would pass against
the zero stub, which is the failure this ticket exists to refuse.

Then re-run the corpus march: `cclasses`, `comphook`, `finput` and `cfileutl`
should all move past `cclasses.pas:676`. The march recipe and the current wall
table are on
[[bug-p-an-unqualified-call-to-a-user-routine-named-read-or-write-is-eaten-by-the-intrinsic]].
