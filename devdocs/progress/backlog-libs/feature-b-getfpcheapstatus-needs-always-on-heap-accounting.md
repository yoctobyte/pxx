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

## 2026-09-05 (frankA) — a SECOND, independent population needs the same symbol

This was filed as the last wall on the FPC compiler-source corpus. It also gates
the FPC **test-suite** corpus, from the other direction and by a different route:

`erroru.pp`, a suite helper unit, uses `TFPCHeapStatus` and `GetFPCHeapStatus`,
and **five conformance skip rows `uses` it** — `tobject1`, `tstring2`,
`tstring4`, `tstring5`, `texception3`. Measured at `36d7e5fd4`, compiler
`e6af001d6c0e3bf2`. Their skip reasons say "object", "strings" and "exception",
three unrelated clusters, so nothing in the skip file could show they share a
blocker; it was found by re-attempting every skip row and clustering on the
compiler's first error rather than on the reason text.

`feature-pascal-corpus-fpc-testsuite` now carries the `blocked-by` edge, so this
ticket's `effective_prio` rises **because the dependency is real**, not because
anyone argued for it: measured p50 → p65 after wiring.

The first symbol in that unit is `ErrorAddr`, which is a separate and probably
cheaper ticket — `feature-b-erroraddr-is-missing-from-system`, also wired. All
three must land before any of the five rows moves, so neither ticket alone is a
win on this population.

### A cheap first move nobody has taken (frankB's, recorded here)

The allocator census line already prints `arenas=1 bump=21`. If arena
bookkeeping already tracks the size and the bump pointer, then **`CurrHeapSize`
and `CurrHeapFree` may fall out of state that exists**, leaving only
`CurrHeapUsed` needing a genuinely new counter. That would turn the design
question at the heart of this ticket — do we pay a counter per allocation — into
a much smaller one.

**Not checked by anyone yet.** Do that before treating the always-on-counters
decision as the starting point; it may be most of the ticket.

## TRIAGE 2026-09-06 (frank-coordinator) — THE IMPLEMENTATION APPEARS TO HAVE LANDED AND THIS ROW IS STILL OPEN

`f6ddab6ef` — *"feat(b): System.ErrorAddr, TFPCHeapStatus and GetFPCHeapStatus, with live
heap accounting"* — names this row's exact subject and its commit message says it delivers
*"the trio recorded as blocking FPC's `erroru.pp` helper, and through it five conformance
skip rows."* All three declarations are present at HEAD:

```
compiler/builtin/builtinheap.pas:343   TFPCHeapStatus = record          { FPC 3.2.2's exact field list and order }
compiler/builtin/builtinheap.pas:380   ErrorAddr: Pointer;
compiler/builtin/builtinheap.pas:399   function GetFPCHeapStatus: TFPCHeapStatus;
```

The commit also records that **the recorded blocker list was already stale when it was
worked**: two skip rows cited `ExitCode` as missing and it reads and writes fine today — *a
third of the blocker was gone and nobody had re-run it.* And the accounting is **new and
unconditional**, which is the hard half this ticket said was the whole ticket: the census
counters are cumulative and behind `-dPXX_ALLOC_CENSUS`, so neither could answer *how much
is in use right now*. Six sites, one per allocator profile per direction, with the cost
measured rather than reasoned (8M alloc/free pairs, min-of-5: 0.52s none, 0.60s shared
helper, 0.55s inlined — the CALL was two thirds of it).

**WHAT I HAVE NOT ESTABLISHED, AND IT IS THE WHOLE REMAINING QUESTION.** I read
declarations, not behaviour. **A symbol being declared is not the same claim as this
ticket's own repro passing** — this row's evidence is `erroraddr := nil` answering
`undefined variable (erroraddr)`, and the sibling's is `cclasses.pas:676` compiling. Neither
has been re-run here, and a builtin unit declaring a name says nothing about whether the
frontend resolves it from user code. **I do not build and I am not resolving somebody else's
ticket on a grep.**

**What settles it, in the owner's hands and cheap:** the two-line repro this ticket already
carries, plus `erroru.pp` compiling, plus the five conformance rows it names (`tobject1`,
`tstring2`, `tstring4`, `tstring5`, `texception3`) — which are now runnable in any checkout,
since `library_candidates/fpc-testsuite` is one `tools/install_lib_candidates.sh
fpc-testsuite` away and took under a minute when frankS fetched it 2026-09-06.

**WHY IT MATTERS BEYOND THIS ROW.** This ticket is a `blocked-by:` edge on
`feature-pascal-corpus-fpc-testsuite` (**Track P, p65, in `working/`**), together with its
sibling. **`blocked-by:` records the RELATIONSHIP; only this folder records its STATE** — so
while this row sits in `backlog-libs`, that P ticket reads as gated to every reader,
including the Track P campaign. If the implementation does satisfy this row, resolving it
retires two edges at once. **Whoever owns Track B: this is a resolve waiting on one
measurement, not a piece of work.**

## MEASURED AT HEAD 2026-09-06 (frankD, Track P, passing through) — THE FEATURE IS LIVE, AND IT IS NOT RETURNING ZEROS

This ticket's own summary names the failure it feared: *"Returning zeros would
make four units compile while the function lies."* **That is not what is there.**
Compiler `855356445cd7`, ordinary build, no `-dPXX_ALLOC_CENSUS`:

```pascal
s1 := GetFPCHeapStatus;  GetMem(p, 1024*1024);  s2 := GetFPCHeapStatus;
  pxx  before: curr=0 size=0 max=0    after: curr=1048576 size=268435456 max=1048576
  fpc  before: curr=0 size=0 max=0    after: curr=1048608 size=1114112  max=1048608
```

`CurrHeapUsed` tracks the megabyte exactly. **The counters are always-on in a
released binary**, which is the "real work" this ticket said had to be decided and
paid for. `ErrorAddr := nil` also compiles and runs
(`feature-b-erroraddr-is-missing-from-system`).

**A single query does NOT discriminate and that is why this needed a delta.** One
call answers 0, and 0 is equally "nothing allocated yet" and "not implemented" —
the collision-with-a-legal-value shape. Only a before/after pair around a known
allocation separates them.

`CurrHeapSize` differs from fpc by two orders of magnitude (268435456 vs 1114112)
because pxx reserves a large arena. Per CLAUDE.md that is a representational
choice, not a defect: both answers are true about their own allocator.

### NOT RESOLVED HERE, and precisely why

The completion criterion in this ticket is a corpus march — `cclasses`, `comphook`,
`finput`, `cfileutl` moving past `cclasses.pas:676` — and that is the **FPC
compiler-source** corpus, a different candidate from `fpc-testsuite`. Not present
in this checkout, not fetched, not run. So: **the feature is measurably
implemented; the four units are unverified.** Whoever owns Track B should re-run
that march rather than trust this note, which covers the function and not the
consumers.

One consumer IS visible in `fpc-testsuite`: `tstring4.pp` prints
`[HEAP] Size: 262144 Kb, Used: 128 bytes` under pxx where fpc prints
`0 bytes / 0 bytes` on the same line. pxx is reporting real accounting where fpc
reports none — more truthful, and still an output difference a corpus comparison
will flag. Worth a decision by the corpus owner, not by this seat.
