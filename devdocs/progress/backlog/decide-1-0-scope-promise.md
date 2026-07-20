---
prio: 55
keep-open: scheme fully DECIDED 2026-07-20 (VERSION/1000 + LTS); stays open only because it gates feature-promo-launch-plan's loud launch — releases are not wanted yet
---

# DECIDE: version scheme — pin count / N, not semver

*(slug is historical: this began as "what does 1.0 promise". The question has
moved; the blocked-by edge from feature-promo-launch-plan is why the slug stays.)*

- **Type:** decide (user call — nobody else can make this one)
- **Track:** A (core owns the gate a release certifies)
- **Status:** backlog — opened 2026-07-12. **Reframed same day (user call): the first official
  release is a 0.1 beta, not 1.0.**
- **Owner:** — (user)
- **Unblocks:** [[feature-promo-launch-plan]]

## DECIDED 2026-07-20 — version = pin count / 1000; the promise lives in LTS

**Premise correction first, because it drives everything.** A version number's
real job is a COMPATIBILITY CONTRACT — "use this, and some compatibility is
granted", the LTS shape. That is what 1.0 or 0.1 actually buys anyone.

*"for now, we just dont do that. latest is almost always better and we check
for regressions ... there are no major breaks planned. instead, more
compatibility is the goal."*

So there is nothing for semver to signal: no breaks are planned, the direction
is MORE compatibility (FPC, gcc, CPython), and the regression matrix means
latest is normally the best build available. A number that exists to warn about
breakage is dead weight when breakage is not the plan. Freed from that, the
number can just be an honest monotonic counter.

**The call: divisor 1000.** Version = pin counter / 1000.

```
now          pin  222  ->  0.222
0.960 LTS    pin  960  ->   97 days   (~3.2 months)
1.000        pin 1000  ->  102 days   (~3.4 months)
1.024        pin 1024  ->  105 days   (~3.5 months)
```
*(measured rate 7.6 pins/day: v9 2026-06-19 -> v222 2026-07-17)*

*"if 1.000 happens to suck, so be it. maybe 1.024 will work better for you."*
1.0 lands somewhere reasonable — about a quarter out — rather than
asymptotically never (the /100000 idea, ~36 years) or next week. The exact pin
is arbitrary and expected to be: once more people work on this the counter
rises faster and lands on odd numbers. That is fine; the number is a count, not
a promise. 1.024 = 2^10 if a round one is wanted.

**Where the compatibility promise actually lives: LTS.** Decoupled from the
version entirely. A chosen pin gets designated LTS with a stated window —
*"0.960 is LTS (3 month)"* — and THAT carries the "some compatibility is
granted" contract. Everything else is just latest-is-best. This is the honest
split: the counter says WHEN, the LTS tag says WHAT IS PROMISED, and neither
pretends to be the other.

### Resolved as a side effect

The "never ship 0.1 first" trap (semver would sort a later `0.03727` above
`0.1`) is moot under /1000: the scheme starts at 0.222, already past 0.1, and
only ever increases. No mixed-scheme ordering hazard exists.

### Canonical counter — SETTLED 2026-07-20

**The current stabilized version is truth.** `VERSION` (the stabilize counter)
is the number; today 222, i.e. **0.222**. `pin.log` is a log — it records which
stabilized builds were blessed as the pinned seed, and is not a version.

Nothing else left open on the scheme.

## HISTORICAL — USER DECISION 2026-07-12: first official release = **0.1 beta**
*(superseded above; kept because the stage-1 bar it specifies is still live)*
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

**WHY the bar is high (user, 2026-07-12): the landscape shifted — this is not 1995.**
Back then a "0.1" compiler was a tarball for hackers who *expected* to patch your Makefile and
would mail you a diff; the version number bought real forgiveness. Today the audience has zero
patience and infinite alternatives: a first-run failure is a permanent bounce, not a bug report.
And the asymmetry is brutal — one bad thread becomes the durable search result, while a good
release merely accumulates quietly. **A 0.x label no longer buys forgiveness: it says "early",
but the reader still expects it to WORK.** Hence: if we publish, it must be genuinely usable and
reasonably stable. That is the whole justification for a 1.0-grade bar under a 0.x number.

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

## Why this stays in backlog (2026-07-20)

`check`'s DECIDED-NOT-MOVED rule flags a decide- ticket that records a decision
and has not moved. This one is an intentional exception, declared via
`keep-open:` in the frontmatter — for TWO reasons now.

**First: it is genuinely undecided again.** The 2026-07-12 "0.1 beta" call was
superseded the same week by the pin-count proposal at the top of this ticket,
which has three open questions of its own. The `## USER DECISION` heading
survives only as history, which is exactly the shape `check` cannot tell apart
from a live decision — hence the explicit opt-out.

**Second, and unchanged: it deliberately gates.** The decision here also IS
"defer, and keep gating": first release is 0.1 beta, and
**the loud moment stays in the pocket** until strangers have run 0.1 and we
have fixed what they broke. `feature-promo-launch-plan` is blocked-by this
ticket precisely so that launch work cannot be picked off the ready queue
early — its own note says "the *launch* is what that blocker gates. The
*visibility* work below is NOT blocked — start it now."

So resolving this would release exactly the work the decision parks. It closes
when 0.1 has actually shipped, at which point the deferred question (what 1.0
promises forever — stage 2) is re-filed as its own decide.
