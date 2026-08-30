---
slug: grant-ir-codegen-call0-cleanup-frame-to-franks
title: "GRANT: ir_codegen.inc for the narrowed xtensa Call0 cleanup-frame work, to frankS"
track: A+S
prio: 50
type: grant
status: backlog
owner: "frankS"
created: 2026-08-30
found-by: frank-coordinator
summary: "frankS may edit ir_codegen.inc as the narrowed Call0 cleanup-frame work requires -- wire the existing enter/leave under Call0, keep TargetHasProcCleanupFrame false under windowed, and delete the stale clause in the comment above that predicate. Wider than the block-level grant it supersedes. File verified clear: b4 moved to elfwriter.inc, frankA is in symtab.inc."
---

# The grant

**frankS may edit `compiler/ir_codegen.inc`** as the narrowed work requires: wire the existing
enter/leave under **Call0**, keep `TargetHasProcCleanupFrame` **false under windowed**, and
**delete the stale clause** in the comment directly above that predicate.

This is deliberately **wider** than `grant-ir-codegen-xtensa-cleanup-arm-to-franks-b4-verified-off`
(`6901fa114`), which was bounded to one block inside `EmitManagedLocalCleanupForTarget`. That
grant is discharged — the work it authorised **was already done** (see below).

## Two conditions

1. **State which routines you enter, not just the file.** The collisions that have actually bitten
   on this file were **semantic adjacencies with zero textual overlap** — `PXXCensusReport`
   calling `PXXSysWrite` from inside `PXXAlloc` was 300 lines from anything a diff would flag.
   A file-level declaration does not surface those; a routine-level one does.
2. **Re-run the ticket's own evidence before building.** See below for why this is not boilerplate.

## File clearance, measured

- **b4** has moved to the `75d2ba662` BSS-sizing segfault — `elfwriter.inc`, disjoint.
- **frankA** is in `symtab.inc` (ParamStr capping + the four unguarded ancestor walks), disjoint.
- Nobody else has touched `ir_codegen.inc`.

## Why the previous grant was a bad dispatch, recorded because the cause is reusable

The superseded grant was filed correctly by every process measure: scope precise, b4's consent
measured rather than estimated, the file verified free three ways rather than on the holder's
word. **None of that was what went wrong.**

The parent ticket's body said xtensa released **1 of 7** managed kinds. At HEAD it releases
**7 of 7** — `e1d7977a2` took it to six, `3a1c1dc73` added the seventh, and
`bug-a-xtensa-scope-exit-releases-one-of-seven-managed-kinds` was already in `done/`. The count
was true when written and false when dispatched.

> **A ticket whose body is a measurement has an expiry date, and nothing in the board prints it.**
> *(frankS, 2026-08-30.)*

The standing rule — *a ranked queue says a ticket is UNBLOCKED, not that it has work left in it* —
was applied to the **blockers** and skipped on the **body**, which is the half that had rotted.
And a stale count is worse than a vague ticket, because **a number reads as checked**.

frankS closed it the right way: not on a code read, but on the ticket's own **downstream
evidence**. Both divergences it named now MATCH the x86-64 oracle at HEAD —
`test_managed_local_release_reuse` (recorded 1/5) and `test_interface_arc` (recorded `freed=1`
where the oracle says `freed=3`). *"The arms are there"* and *"they work"* are two claims, and a
code read is the same act that produced the stale one.

## The finding that fell out

`bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa` [A p25] gives two reasons xtensa
sits outside `TargetHasProcCleanupFrame`: the Call0-only exception runtime, **and** *"its
managed-local arm handles `AnsiString` alone"*. The second died with those same two commits. So
the release sequence a cleanup frame needs as its landing pad **already exists on xtensa and is
complete**, and the remaining work is narrower than that ticket describes — wire the existing
enter/leave, not "ESP-campaign work of unstated size". Ticket updated, deliberately **not**
re-priced: p25's argument (needs a raise crossing a frame that owns a managed local) is untouched
by which blocker remains.
