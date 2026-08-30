---
slug: grant-ir-codegen-xtensa-cleanup-arm-to-franks-b4-verified-off
title: "GRANT: ir_codegen.inc's xtensa managed-cleanup arm to frankS, b4 verified off the file"
track: A+S
prio: 55
type: grant
status: done
owner: "frankS"
created: 2026-08-30
found-by: frank-coordinator
summary: "Discharges grant-the-xtensa-cleanup-arm-in-ir-codegen-to-track-s. frankS may edit the `if TargetArch = TARGET_XTENSA then` block inside EmitManagedLocalCleanupForTarget at ir_codegen.inc:10680 and nothing else in that file. b4's release verified three independent ways, not relayed from its word alone."
---

# The grant

**frankS may edit** the `if TargetArch = TARGET_XTENSA then` block inside
`EmitManagedLocalCleanupForTarget`, `compiler/ir_codegen.inc:10680`, **and nothing else in
that file.** Scope is the parent ticket's, unwidened.

Given 2026-08-30 by the coordinator, and **filed at the moment of giving**. An unfiled grant
does not read as missing — it reads as *covered*, because a neighbouring ticket covers the
same file. That failure already cost a bad dispatch this session.

# Why it needed a coordinator and not just the ticket

frankS's own read, which is correct: the parent ticket specifies the scope precisely, carries
b4's measured footprint and its consent, and is better-specified than most things acted on
tonight. **The one thing a ticket cannot answer is whether the other holder is still on the
file** — that is live state, and it expires.

# b4's release, verified three ways

Not relayed from the holder's word alone (*verify against a source the claimant did not
choose*):

1. b4 stated it directly: *"Tree clean, nothing held."*
2. Its tree shows **only a staged ticket move** — no source file modified.
3. It is dispatched to `bug-a-twenty-new-cross-target-rows-compare-stdout-without-the-exit-code`,
   which edits **Makefile recipe lines**. Disjoint from `ir_codegen.inc` by construction rather
   than by promise.

# Why the work matters

xtensa's arm releases **1 of 7** managed kinds where every other backend releases 7 — a leak on
scope exit for six kinds. frankS has 103 running xtensa programs to check it against, and
riscv32's arm is a verbatim port away, which is why b4 was right to decline re-deriving it.

# Standing constraint on this file

`ir_codegen.inc` has carried deliberate dual occupancy tonight (`715a2e1b3`). Anyone else
entering it must state their routine, not just the file — the collisions that matter here have
been **semantic adjacencies with zero textual overlap**, which no diff-based check can see.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
