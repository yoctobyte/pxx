---
slug: decide-should-forwardlint-join-the-mandatory-per-fix-loop
title: "Should forwardlint join the mandatory per-fix loop now that it is silent?"
track: U
type: decide
status: backlog
found: 2026-08-29
found-by: frank-coordinator (raised by frank-optimize-b4)
prio: 55
supersedes:
  - decide-should-the-fpc-seed-canary-be-in-the-mandatory-loop
summary: "Collapses the two tickets that both asked what may join the three-line per-fix loop. make compiler/pascal26 compiles compiler.pas WITH pxx, so the loop and the self-host fixedpoint are blind BY CONSTRUCTION to a construct pxx accepts and FPC rejects -- and FPC is the bootstrap seed. tools/forwardlint.py models FPC's resolution, runs in 4.1s, and as of 7aba316be is silent on a clean tree, which removes the one argument that kept it out. Five measured instances of the seed breaking while the loop stayed green. Recommendation: option 1, narrowly. The edit is to CLAUDE.md's gating section, so only the owner makes it."
---

# Decision: does `tools/forwardlint.py` join the mandatory per-fix loop?

**This is the owner's call because the answer edits `CLAUDE.md`**, which no agent
touches on a peer's say-so. Recording the fork, the evidence and a recommendation
so the decision is cheap.

## The fork

`make compiler/pascal26` compiles `compiler.pas` **with pxx**. So the per-fix loop
and the self-host fixedpoint are blind to FPC-only breakage **by construction** —
pxx resolves names across the whole unit, FPC in source order. A change that breaks
the FPC seed passes the entire gate. That is not hypothetical: it happened on
2026-08-26 and was caught by a benchmark, not by the gate.

`tools/forwardlint.py` models FPC's resolution and catches exactly that class.
It is already wired into `tools/gate.sh` (before the mode `case`, so no mode can
skip it) — but `gate.sh quick` is **optional** per fix and only mandatory before a
pin. The question is whether forwardlint joins the three-line mandatory loop.

## What changed today

Until `7aba316be`, forwardlint had **one permanent known exception** (`LowerCase`),
and *a lint carrying a permanent exception is one people learn to scroll past.*
That was the entire argument for keeping it out of the loop, and it is now gone:
**forwardlint is silent on a clean tree.** frank-optimize-b4, who landed the fix:
*"If you want forwardlint in the loop, it is ready now."*

Track T independently runs both halves — the lint **and** a real
`fpc -Mobjfpc compiler/compiler.pas` — and both pass at `ecc00ae77`. Worth keeping
in view: the lint is a *model* of FPC's resolution; only FPC is FPC.

## Options

1. **Add forwardlint to the mandatory loop.** Cost is seconds (it is a source
   scan, not a build). Closes a hole the fixedpoint cannot see by construction.
   Cost against the loop's own doctrine: the loop is deliberately three lines and
   CLAUDE.md says *do not widen this loop* in strong terms.
2. **Leave it in `gate.sh` only** (status quo). It runs before every pin, and
   Track T runs both halves asynchronously. FPC breakage can then live on master
   between pins.
3. **Leave the loop alone and rely on Track T's real-FPC compile**, treating the
   lint as belt-and-braces.

## Recommendation

**Option 1**, narrowly. The loop's "do not widen" rule exists to stop agents
running ten-minute suites for coverage Track T already provides asynchronously.
Forwardlint is the opposite of that case: it is seconds, not minutes, and it
covers a failure the loop is blind to **by construction rather than by breadth**
— so no amount of Track T sweeping makes it redundant for the person about to
push. The rule's own rationale does not reach it.

Against my own recommendation, honestly: every widening has been argued this way,
and "it is only seconds" is how a three-line loop becomes six. If the answer is no,
option 3 is coherent and nothing is broken.

**Whoever resolves this: the edit is to `CLAUDE.md`'s per-fix loop section, and
only the owner makes it.**

---

## COLLAPSED 2026-08-30 (frankD): this and the FPC-seed-canary ticket are one question

`decide-should-the-fpc-seed-canary-be-in-the-mandatory-loop` [U p55] asked the
same thing from the other end, and its **option 4 is this ticket's option 1** —
the same tool, the same cost, the same fork. Two tickets, one answer.

Its evidence log is the richest thing either had and is **preserved intact** at
`rejected/decide-should-the-fpc-seed-canary-be-in-the-mandatory-loop.md`. It is
in `rejected/` because it is no longer the open question, **not** because it is
wrong; read it before answering this one. In brief, it records:

- **Five measured instances** of the loop being green while the FPC seed build
  was red — frankwasm twice in one day (`WasmEmitCall`, `WasmEmitIndArgs`),
  frankA once while landing wall 6 (`35f485537`), and Track P twice in one
  session (`3a011ed6f`).
- **Option 1 of that ticket — a targeted "watch for this edit shape" convention —
  is empirically disproven.** It relies on a lane recognising its own edit
  shape, and the lane missed both of its own instances.
- **The second Track P instance is a different shape**: the forwards *existed*
  and a later refactor lifted a caller above them. So *"I already added
  forwards"* was true and useless. **A guard whose correctness depends on
  relative position is re-broken by any edit that moves either side, and the
  person who added it will remember adding it.**
- The 4.1s figure is a **correction** of an earlier ~1s claim that measured a
  version which does not work on this repo (17 false failures on a tree FPC
  builds clean). The shipped tool expands `compiler.pas`'s `{$include}` chain —
  206,768 lines in 4.1s, 17 → 0, ~11x faster than the 46s FPC build.

## On generalising this to a rule — deliberately not done

It is tempting to re-file this as *"what is the general rule for what may join
the three-line loop?"*, since the question has now been asked twice and will be
asked again. **I recommend against it, and the reason is this digest's own
finding:** a decision sits when it is priced wrong, and turning a concrete
yes/no about a verified 4-second lint into an abstract policy question makes a
cheap decision expensive. That is the mistake the rust-branch ticket made by
accident; it should not be made here on purpose.

So the fork above stands as written. **If the owner wants the general rule, it
is available for free as a second sentence** — the natural one, already implied
by both tickets and by the loop's own rationale:

> A check may join the mandatory loop if it is **seconds not minutes**, and it
> covers a failure the loop is blind to **by construction rather than by
> breadth** — because no amount of Track T sweeping makes the first kind
> redundant for the person about to push, and Track T already covers the second.

That rule admits forwardlint and excludes every suite the "do not widen" rule
was written to keep out. Stating it would pre-answer the third instance. But it
is an optional bonus on this decision, not a precondition for it.

