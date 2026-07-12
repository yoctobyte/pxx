---
prio: 55
---

# DECIDE: first release is 0.1-BETA — a 1.0-grade bar under a modest number

- **Type:** decide (user call — nobody else can make this one)
- **Track:** A (core owns the gate a release certifies)
- **Status:** backlog — opened 2026-07-12. **Reframed same day (user call): the first official
  release is a 0.1 beta, not 1.0.**
- **Owner:** — (user)
- **Unblocks:** [[feature-promo-launch-plan]]

## USER DECISION 2026-07-12: first official release = **0.1 beta**
**A 0.x beta carries no compatibility promise**, so the hard question (what does 1.0 guarantee
*forever*) is **deferred**, not answered now. But note what the user did NOT do: he did not lower
the *bar*. The 0.1 criteria (stage 1) are a maturity bar most projects would call 1.0. **The
modesty is in the version number.**

**A release is NOT a launch — keep them separate.**
- **0.1 = a real release, quietly announced.** Tarball, checksums, an install that actually
  works, docs that match. Announce in low-stakes places (devlog, Pascal forums, own channels).
  Let strangers run it and watch what breaks.
- **The big coordinated blast stays in the pocket.** Not because 0.x is embarrassing (HN is fine
  with 0.x when you are honest) — but because the one-shot resource is **the moment**, not the
  version number. A 0.1 that gets front-paged and then 404s on install burns it exactly as
  thoroughly as a bad 1.0 would.
- Sequence: **0.1 beta → real feedback → fix what strangers break → then the loud moment**
  (at 0.2, at 1.0, whenever it is earned).

## Stage 1 — the 0.1-beta bar (USER-SPECIFIED 2026-07-12)
**The modesty lives in the NUMBER, not the bar.** 0.1 must meet what most projects would ship as
1.0; we simply decline to call it that. Criteria, in the user's terms:

1. **Feature complete** — against the project's own goals, not against "every language feature
   that exists".
2. **Tested** — the gates green: `make test`, self-host fixed point, the cross matrix, the
   corpora.
3. **Most project targets achieved** — the targets we set out to hit, hit.
4. **Actually usable** — someone who is not us can install it and do real work.
5. **No longer under heavy development / no big structural changes.** *Refinement:* a compiler is
   under development forever, so that criterion can never be ticked as literally written. What it
   MEANS — and what we should write — is **no big structural changes pending**: the architecture
   is settled, the IR and lane structure are not about to be re-cut, and new work is features and
   fixes rather than foundations. That IS tickable.

**Consequence, recorded as a deliberate choice:** this makes 0.1 a **substantial milestone, not a
cheap rehearsal**. It pushes the first release well out, and the "ship early, learn from
strangers" logic does not apply to it. The *release ≠ launch* split still holds
([[feature-promo-launch-plan]]), but 0.1 is not a quick win — by design.

Still to answer within that bar (descriptions, not guarantees):
- **What works** — which frontends, which targets, which corpora actually run.
- **What is known rough** — say it out loud; a release that names its own sharp edges earns more
  trust than one that hides them.
- **What is explicitly out of scope** (experimental frontends R/Z, GUI, optimizer output
  stability, ABI stability).
- Release mechanics: install path, `SHA256SUMS` + signature ([[feature-release-checksums-repro]]),
  docs that match reality.

**Tone: understatement with receipts.** Modesty's failure mode is underselling until nobody
looks. State the facts flatly and let them work — "it compiles itself to a byte-identical binary,
and it builds SQLite without libc on an ESP32" needs no adjectives; it is *more* impressive
delivered dry. Be modest about the version number and the claims we cannot back; be plain about
the ones we can.

## Stage 2 — DEFERRED: what does 1.0 promise?
Not on the table until 0.1 ships. Keep the analysis below for then; do not let it block 0.1.
(Note: with 0.1 set at the maturity bar above, 1.0's distinguishing content is likely a
**compatibility promise** — "code that compiles under 1.0 keeps compiling through 1.x" — rather
than more features.)

## The trap this ticket exists to avoid
"So much on the to-do" is a feeling that **never goes away** — the backlog of a compiler grows
forever, because every language you accept and every target you add generates more of it. If
1.0 means *"the TODO list is short"*, **1.0 never ships.** That is the default failure mode and
it is worth naming.

## The reframe
**1.0 is a promise, not an absence of TODO.** It is a *scoped guarantee* about what works and
what will keep working. Everything outside the scope is 1.1+, and saying so out loud is not a
weakness — it is what a version number MEANS to everyone else.

Concretely, 1.0 should answer:
1. **Which frontends** are in scope, and at what surface? (Pascal, surely. C — at what level:
   "compiles the corpus we ship" vs "C99"? Rust/Zig are explicitly experimental → out.)
2. **Which targets** are supported vs. best-effort? (x86-64 native surely; i386/aarch64/arm32
   proven by self-host; riscv32/xtensa emit-only bare-metal.) Say which are *promised*.
3. **What is the stability promise?** The important one. Suggested: *"code that compiles under
   1.0 keeps compiling through 1.x"* — a source-compatibility promise, not a feature-count one.
4. **What is explicitly NOT promised** at 1.0 — optimizer output stability, ABI stability for
   the IR, the experimental frontends, GUI. Naming the exclusions is what makes the inclusions
   credible.

## Why a release gates the loud moment
The launch spends a one-shot resource (see [[feature-promo-launch-plan]]). It needs a working
install and a claim that survives an hour of hostile clicking. Both require knowing what we are
claiming. So: scope 0.1 → ship it → learn from real users → *then* the loud moment.

## Log
- 2026-07-12 — opened as "what does 1.0 promise". Reframed the same day (user call): **first
  official release is 0.1 beta**, and 1.0's compatibility promise is deferred to stage 2.
- 2026-07-12 — **correction.** The agent first read the maturity criteria (feature complete,
  tested, targets achieved, usable, no big structural changes pending) as a *1.0* definition and
  assumed 0.1 would therefore be a cheap early rehearsal. Wrong: those criteria ARE the **0.1**
  bar. The user is holding a 1.0-grade bar and deliberately shipping it under a 0.x number — the
  modesty is in the number, not the standard. Consequence recorded in stage 1: 0.1 is a
  substantial milestone, not a quick win, and the "ship early, learn from strangers" argument does
  not apply to it. Release ≠ launch still holds.
