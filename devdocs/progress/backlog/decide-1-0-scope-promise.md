---
prio: 55
keep-open: REOPENED 2026-07-20 — the version scheme is undecided again (pin-count proposal supersedes 0.1-beta), and this still gates feature-promo-launch-plan's loud launch
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

## SUPERSEDED 2026-07-20 — the number changes, the bar does not

The user's new take: **drop semver entirely.** Version = the pin counter,
divided down. We are already at pin 222, so `/100000` reads **0.00222** — we
"passed beta 0.001" around pin 100 and are monotonically approaching 1.0.
Releases, if any, are just odd-numbered checkpoints ("pxx 3727"), not marketing
versions.

*"sod off with this old fashioned naming convention. happy to make releases,
but not yet, and if, they'd be just some odd number checkpoint (3727) or so."*

**What survives from the 2026-07-12 decision:** the maturity BAR below (stage 1
criteria) is unchanged and still the gate — feature complete, gates green,
targets hit, actually usable, no big structural churn. The modesty was always
in the number; this proposal simply stops pretending the number means anything
else. **What dies:** "0.1 beta" as the label, and with it the whole semver
framing of stage 2.

### Measured, 2026-07-20

```
VERSION            222      incremented per stabilize
pin.log entries    213      pins are a SUBSET of stabilizes — already diverged by 9
first pin  v9      2026-06-19
last  pin  v222    2026-07-17        ~7.6 pins/day over 28 days
```

| divisor | 1.0 at | at 7.6 pins/day |
| --- | --- | --- |
| 1,000,000 | 1M pins | ~360 years |
| **100,000** | 100k pins | **~36 years** |
| 10,000 | 10k pins | ~3.6 years |

Precedent: Knuth's TeX asymptotically approaches π, METAFONT approaches e —
never arriving is the point, and it is an honest way to say "this is not
finished and will not claim to be".

### OPEN — three things this needs settled

1. **Divisor.** `/100000` puts 1.0 ~36 years out at the measured rate, i.e.
   effectively asymptotic. That is coherent IF never-arriving is intended. If
   "working to 1.0" means actually arriving in this project's lifetime,
   `/10000` (~3.6 years) is the honest divisor. The number is a promise either
   way — pick which promise.
2. **Canonical counter.** `VERSION` counts *stabilizes* (222); `pin.log` counts
   *pins* (213). Already 9 apart and drifting. "Pin #" says count pins, but the
   machinery increments on stabilize. Pick one; make the other stop pretending
   to be a version.
3. **Release identity.** Recommendation: the INTEGER leads — tarball and
   `--version` say `pxx 3727`; the fraction `0.03727` is cosmetic progress. The
   integer is the truth (a binary that reproduced itself and was blessed); the
   fraction is the story.

### One hard constraint — do NOT ship a 0.1 first

`0.03727` parsed as semver is minor=3727; `0.1` is minor=1. So a later
`0.03727` sorts ABOVE `0.1` in semver but BELOW it numerically. Mixing the two
schemes breaks ordering in package managers permanently, and irreversibly —
you cannot unpublish a version. Nothing has shipped yet, so adopting the pin
scheme directly costs nothing; shipping "0.1" first poisons it forever.

---

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
