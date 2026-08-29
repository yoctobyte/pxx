---
slug: decide-should-forwardlint-join-the-mandatory-per-fix-loop
title: "Should forwardlint join the mandatory per-fix loop now that it is silent?"
track: U
type: decide
prio: 50
status: backlog
found: 2026-08-29
found-by: frank-coordinator (raised by frank-optimize-b4)
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
