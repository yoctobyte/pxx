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
