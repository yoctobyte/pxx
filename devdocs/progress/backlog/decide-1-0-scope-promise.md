---
prio: 55
---

# DECIDE: first release is 0.1-BETA — scope it (1.0's promise is deferred)

- **Type:** decide (user call — nobody else can make this one)
- **Track:** A (core owns the gate a release certifies)
- **Status:** backlog — opened 2026-07-12. **Reframed same day (user call): the first official
  release is a 0.1 beta, not 1.0.**
- **Owner:** — (user)
- **Unblocks:** [[feature-promo-launch-plan]]

## USER DECISION 2026-07-12: first official release = **0.1 beta**
This is the better plan and it unblocks everything immediately. **A 0.x beta carries no
compatibility promise**, so the hard question below (what does 1.0 guarantee *forever*) is
**deferred**, not answered now. The bar drops from "a promise I must keep" to "here is what
works today, honestly labeled."

**A release is NOT a launch — keep them separate.**
- **0.1 = a real release, quietly announced.** Tarball, checksums, an install that actually
  works, docs that match. Announce in low-stakes places (devlog, Pascal forums, own channels).
  Get strangers to run it and watch what breaks. This is a **rehearsal** — it is how we find out
  `curl | sh` fails on a distro we never tested.
- **The big coordinated blast stays in the pocket.** Not because 0.x is embarrassing (HN is fine
  with 0.x when you are honest) — but because the one-shot resource is **the moment**, not the
  version number. A 0.1 that gets front-paged and then 404s on install burns it exactly as
  thoroughly as a bad 1.0 would.
- Sequence: **0.1 beta → real feedback → fix the embarrassing stuff → then the loud moment**
  (at 0.2, at 1.0, whenever it is earned).

## Stage 1 — scope 0.1 (EASY; this is a description, not a guarantee)
Answer three questions, no promises attached. An afternoon's work.
1. **What works** — which frontends, which targets, which corpora actually run.
2. **What is known broken / rough** — say it out loud; a beta that names its own sharp edges
   earns more trust than one that hides them.
3. **What is explicitly out of scope** for 0.1 (experimental frontends R/Z, GUI, optimizer
   output stability, ABI stability).

Plus the release mechanics: install path, `SHA256SUMS` + signature
([[feature-release-checksums-repro]]), docs that match reality.

## Stage 2 — DEFERRED: what does 1.0 promise?
Keep the analysis below for when 1.0 is on the table. Do not let it block 0.1.

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
- 2026-07-12 — opened as "what does 1.0 promise". Reframed the same day: **first official release
  is 0.1 beta** (user call). 1.0's promise deferred to stage 2; 0.1 needs only an honest
  description of what works, what is rough, and what is out of scope. Release ≠ launch.
