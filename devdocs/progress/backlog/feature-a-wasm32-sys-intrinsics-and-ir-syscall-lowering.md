---
track: A
prio: 60
type: feature
blocked-by: [decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal]
status: backlog
owner: ""
summary: "The last 36 unlowered bodies in compiler.pas on wasm32: 35 sys builtins (writeELF*, writeU8/16/32/64, LoadFile) plus IR_SYSCALL (value op 54), which is the same question wearing a different hat. Blocked on the Track U decision, not on any missing mechanism. Filed so the ranker can SEE that a U item is holding a p60 lane — the edge did not exist, so prio propagation had nothing to work with and the decision sat at 40."
---

# wasm32: the sys intrinsics and `IR_SYSCALL`, the last 36 bodies

**3698 of 3734 bodies in `compiler.pas` lower on wasm32.** The 36 that do not
are:

- **35 sys builtins** — `writeELF*`, `writeU8/16/32/64`, `LoadFile`
- **`IR_SYSCALL`** (value op 54) — the same question in different clothing

Every one is **blocked on
`decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`**, not
on a missing mechanism. There is no implementation work that can begin before the
decision, and no way to guess a direction that would not have to be redone.

*(Denominator note: 3662 → 3734 across the last merge, so this count is not
comparable to phase 9g's without saying so.)*

## Why this ticket exists at all

It is the **edge**, not the work.

The decision was sitting at **p40**. The only ticket declaring it as a blocker
was already in `done/`, so the ranker saw a U item that blocked nothing live —
and prio propagation, which is the mechanism that is supposed to raise a blocker
to the priority of what it unblocks, **had nothing to propagate along.** The lane
it actually holds is `feature-target-wasm` at **p60**.

The edge was not put on the umbrella deliberately: the umbrella is not blocked,
only its last 36 bodies are, and marking a mostly-live ticket `blocked-by` would
misreport the lane. So the blocked slice gets its own ticket and carries the edge.

> **A blocker with no live dependents is indistinguishable from a blocker nobody
> needs.** The board ranks what it can see, and work that exists only on a branch
> — or only in a lane's own head — contributes no priority to the thing holding
> it up. This is the same rule as *a ticket that is not on master does not
> exist*, one level out: **an unfiled dependency does not merely hide the work,
> it silently under-ranks the decision.**

## When the decision lands

Re-file as ordinary Track A work, or resolve this and let the wasm lane pick it
up directly — a U item that turns out to be plain work once decided belongs in
the owning lane, not in U.
