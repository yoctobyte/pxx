---
track: A
prio: 15
type: chore
blocked-by: []
summary: "PXXSysLseek's rv32 comment in compiler/builtin/builtinheap.pas ends with a NOTE saying the sibling comment in platform_backend.pas 'still says the plain form is tolerated by qemu-user'. That sibling was corrected on 2026-08-30, so the clause is now false. Three-line deletion in a Track A file; filed rather than edited from Track B."
status: backlog
owner: unassigned
---

# Trim the now-false cross-reference in `PXXSysLseek`'s rv32 comment

- **Type:** chore (stale comment) — **Track A** (`compiler/builtin/**`).
- **Filed:** 2026-08-30 by frankB (Track B), as a direct consequence of resolving
  [[bug-b-platform-backend-rv32-comment-claims-plain-lseek-is-tolerated]].

## What is stale

`compiler/builtin/builtinheap.pas`, in `PXXSysLseek`'s `CPU_RISCV32` arm, the
comment closes with:

> *"NOTE the sibling comment in that same file's rv32 block still says the plain
> form is tolerated by qemu-user for small offsets. The strace above falsifies
> that for the RETURN VALUE case, which is the one this helper needs.
> bug-b-platform-backend-rv32-comment-claims-plain-lseek-is-tolerated"*

That sibling comment was corrected on 2026-08-30. It no longer says the plain
form is tolerated; it now states that rv32 has no plain lseek at all and carries
the same strace. So the NOTE points at a contradiction that has been removed, and
the ticket slug it cites is closed.

## What to do

Delete the NOTE paragraph. **Keep everything above it** — the explanation of
`_llseek`'s five-argument shape, the strace, and the "must not drift" pointer at
`PalBackendSeek` are all still correct and are the reason the arm looks the way
it does. Only the "the sibling still disagrees" clause has expired.

Optionally reciprocate the pointer: `platform_backend.pas` now names
`PXXSysLseek` as the sibling that must not drift, and this comment could name it
back symmetrically.

## Why file a three-line deletion

Because it is exactly the defect the parent ticket was about: a comment asserting
a fact about *another* file, with nothing that re-checks it when that file moves.
Leaving it would reproduce the failure while closing it — and the parent's whole
finding is that the wrong statement is the one a reader meets first.

Not edited directly because `compiler/builtin/**` is Track A's ground and the
finding came from Track B.

## Gate

Track A's: `make compiler/pascal26` (the self-host fixedpoint) — a
comment-only change, so nothing else is expected to move.
