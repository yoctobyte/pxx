---
slug: feature-b-erroraddr-is-missing-from-system
title: "System.ErrorAddr is missing, and it is the first of three symbols one suite helper needs"
track: B
prio: 40
type: feature
status: backlog
found: 2026-09-05
found-by: frankA
owner: ""
blocked-by: []
summary: "FPC's System unit exposes the writable global `ErrorAddr: Pointer` (the address a runtime error was raised at, cleared by a handler that recovers). pxx has no such symbol: `erroraddr := nil` gives `undefined variable (erroraddr)`. Measured 2026-09-05 at 36d7e5fd4, compiler e6af001d6c0e3bf2. It is the FIRST error in `erroru.pp`, a helper unit that FIVE conformance skip rows use -- tobject1, tstring2, tstring4, tstring5, texception3 -- so it is one of exactly three symbols standing between those rows and a compile; the other two are TFPCHeapStatus and GetFPCHeapStatus, which are feature-b-getfpcheapstatus-needs-always-on-heap-accounting and are the harder half. Unlike that one this is probably cheap: a global plus whatever the runtime-error path already knows about where it faulted. NOT YET ESTABLISHED and the reason this is a ticket rather than a fix: whether pxx's error path HAS a raise address to publish, and whether declaring the global without populating it truthfully would be the stub CLAUDE.md refuses -- a caller that prints ErrorAddr after a recovered error would print nil with no diagnostic."
---

# System.ErrorAddr is missing from System

## What was measured

`erroru.pp` (FPC test-suite helper, `library_candidates/fpc-testsuite/tests/test`)
opens with `exitcode := 0; erroraddr := nil;`. pxx:

    pascal26:82: error: undefined variable (erroraddr)
    pascal26:106: error: unknown type: TFPCHeapstatus
    pascal26:110: error: undefined variable (GetFPCHeapStatus)

Three symbols, one unit, and the unit is a dependency of five skip rows.

## Why it was not visible before

The five rows carry skip reasons that name three DIFFERENT clusters — "object",
"strings" and "exception" — because each reason was written from the row's own
subject rather than from where it actually stops. Nothing in the skip file could
have shown that they are one unit. It was found by re-attempting every skip row
and clustering on the compiler's first error instead of on the reason text.

## The two open questions

1. **Does our runtime-error path know the address?** `ErrorAddr` is only
   meaningful if something can populate it. If the raise path already carries a
   fault address, this is a global plus one assignment.
2. **Is a declared-but-never-populated `ErrorAddr` a stub we may not ship?**
   The four units in the sibling ticket would compile if `GetFPCHeapStatus`
   returned zeros, and that was refused for exactly this reason. The same test
   applies here and has not been answered: a program that prints `ErrorAddr`
   after a recovered runtime error would print `nil` with no error. Answer this
   before writing the global, not after.

Both are measurements, not decisions — check the error path before treating this
as a design question.

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
