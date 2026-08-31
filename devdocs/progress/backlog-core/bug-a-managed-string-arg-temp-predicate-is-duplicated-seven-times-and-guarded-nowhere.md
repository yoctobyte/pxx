---
slug: bug-a-managed-string-arg-temp-predicate-is-duplicated-seven-times-and-guarded-nowhere
title: "One concept, seven copies, zero guards: the managed-string arg-temp decision in ir.inc"
track: A
type: bug
prio: 20
status: backlog
found: 2026-08-29
found-by: frankwasm
---

> **Refiled 2026-08-30 out of `chore-a-grant-wasm32-lane-holds-ir-inc-for-the-11207-mistyping`.**
> That ticket was 80% grant bookkeeping for a mechanism that no longer exists, and
> 20% this — a measured seven-site design flaw that lived nowhere else. Closing it
> by slug shape, with its five siblings, would have deleted the only record of the
> defect. The grant half is gone; the investigation below is verbatim.
>
> **Prio stays 20 because of REACH, not because it was a wasm ticket.** The
> mistyped retain and release cancel out on every register backend, so no native
> target can observe it today. It is a latent defect in shared IR, which is exactly
> the kind that stops being latent when a backend changes.

## The defect

frankwasm re-derived its own ticket before touching anything and found the
load-bearing claim in it false. The ticket said *"the same file already gets this
right one site over"* at `ir.inc:11329`. On current master that line is in a
`tyVariant` **default-parameter** branch, unrelated to the managed-string arg
temp. It then checked every candidate: all four `argIsManagedTemp` predicates
(11060, 11305, 11813, 12931) and all seven
`hiddenArgSym := AllocVar('', tyAnsiString)` sites (11069, 11360, 11532, 11704,
11831, 12825, 12951). **Not one tests `IsArray`.**

So there is no correct sibling to copy from. Seven sites, one concept — *does
this parameter want an owning managed-string temp?* — and zero guarded. By
`root-cause-over-microfix`'s own counting rule that is a design flaw, not a typo
at one site, and the likely right fix is **one predicate every site calls**,
deleting six copies rather than adding a seventh clause.

**The grant therefore covers the managed-string arg-temp decision across all its
sites in `ir.inc`, not the single line `:11207`.** Granting the line number would
have forced the microfix the repo has a document telling us not to make, and
would have left six sites for someone to rediscover.

**Where the fix lands:** `compiler/ir.inc`. Gate is Track A's — `make
compiler/pascal26` (which IS the fixedpoint) plus the repro, and cross-target
confirmation, because the change is backend-visible.

**Do the measurement before the edit:** a repro exercising the direct,
constructor, indirect, virtual and interface call paths with an
open-array-of-string argument, to establish which of the seven sites can actually
fire. Shape implying a bug is not the bug, and the count of unguarded sites is
what justifies consolidating rather than patching.
