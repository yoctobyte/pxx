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


---

## RESOLVED 2026-08-30 — **status quo. It does not join the loop.**

Owner:

> *"this is only about FPC bootstrapping, right? and while 5 seconds doesnt sound
> like much, a thousand times a day is much. we actually did a lot of effort to
> have a very quick self-check (around 40 seconds now or so, if all is well).
> adding 10% to that is significant for something we only have to check every so
> often (on major pinned versions)"*

### The ruling, and the rule behind it

**Gate a property at the boundary where it is consumed.** The FPC seed is
consumed at a cold start and at a pin. That is where it is gated. It does not
belong in a per-edit loop, and no amount of instance-counting changes that,
because the instances are all *between* pins — where nothing consumes the seed.

This supersedes the rule the recommending agent offered ("seconds not minutes,
blind by construction not breadth"). That one is a property of the *check* and
drifts with a stopwatch; this one is a property of the *thing checked*.

### Three things the tickets got wrong, all in the same direction

1. **The status quo already does what the ruling asks, and more.**
   `tools/gate.sh` runs forwardlint before the mode dispatch — every mode, not
   skippable — **and** starts a real `fpc` seed build in the background,
   concurrent with the other steps and skipped when compiler sources are
   untouched. `gate.sh quick` is REQUIRED before a pin. So the seed is checked
   at every pin boundary, by the actual compiler rather than a model of it, at
   near-zero marginal wall time.
2. **Wiring it into `make compiler/pascal26` would have double-charged.**
   `gate.sh quick` runs the build, so the proposal taxes the mandatory pin gate
   as well as every dev rebuild — the one path that already covers this.
3. **The cost figure was stale by 5x.** `gate.sh` documented forwardlint at
   `~1s`; measured 2026-08-30 on plexus, three runs: 5.71 / 5.48 / 5.23s. All
   three tickets inherited the wrong number and argued cheapness from it.
   Corrected in `tools/gate.sh` in the same commit as this resolution.

### The evidence the tickets cited argues the other way

The 2026-08-30 duplicate forward — presented in this ticket as *"the stronger
form of the argument"* — happened because the break was **visible** and two
lanes raced to fix the same absence within 60 seconds, landing two forwards for
one gap. Waiting for the pin would have meant one person fixing it once, with a
tool that names the exact site and the FPC error text.

**Six lanes independently discovering and reacting to a red seed cost more than
the red seed did.** Making it more visible, more often, makes that worse. The
instance count was being read as severity when it was mostly duplication.

### What was NOT disputed

`forwardlint` is a good tool and this changes nothing about it. It stays wired
into `gate.sh` in every mode; it caught both directions of the 2026-08-30 break
(missing forward AND duplicate forward), and it is what made the duplicate a
two-line fix instead of a bisect. The question was only whether it becomes
mandatory per fix, and the answer is no.

### Also fixed, because it is what sent an agent into an unnecessary bootstrap

`Makefile`'s seed-missing message said *"Run: make bootstrap"* — the FPC cold
start, almost never what the reader needs, since the committed stable binary
self-seeds. It now names the self-seed first and `make bootstrap` last, as what
it is.

While rewriting it, one further piece of stale advice was found by measurement:
**the `touch`-after-copy step is no longer needed.** The `$(COMPILER_STAMP)`
mechanism closed the copied-in-seed no-op, so a seed newer than every source
still builds — verified by `cp`ing pinned over the binary, removing the stamp,
and getting `converged after 2 round(s)`. **CLAUDE.md still tells readers to
`touch` the sources after seeding a tree from outside.** That is the owner's
file and is left for the owner; see
[[bug-d-claude-md-still-prescribes-a-touch-the-stamp-fix-made-unnecessary]].
