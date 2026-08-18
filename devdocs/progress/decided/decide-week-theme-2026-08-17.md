---
track: U
prio: 70
type: decide
blocked-by: []
summary: "What should the next week of work aim at? Measured: the bug backlog already peaked (61 on 08-03 -> 32 now) and 65% of open tickets are features, so this is no longer a burn-down question. Three candidate themes with the numbers behind each."
status: decided
---

# Decide: the theme for the coming week

**Read time ~2 minutes. Nothing is blocked on this** — workers run their ranked
queues until it is answered. It changes what they aim at, not whether they run.

## What the numbers say (measured 2026-08-17, direct file counts)

Open-bug inventory over time — it PEAKED three weeks ago and is falling:

| date | open bugs | open features |
| --- | --- | --- |
| 2026-07-27 | 9 | 124 |
| 2026-08-03 | **61** (peak) | 127 |
| 2026-08-10 | 54 | 143 |
| 2026-08-17 | **32** | 146 |

Composition today: **146 open features vs 32 open bugs** (65% / 14%). So "burn
down the backlog" is not the question any more; there is barely a backlog.

Where the 32 live: **N 17**, B 6, C 3, T 2, P 2, **A 1**, O 1. Caveat stated
plainly, because it was a real correction: this counts FILED TICKETS, not
defects. Track A having 1 open bug means nothing is queued, not that the core is
clean — yesterday's corpus walk produced five A/P bugs in an afternoon from code
with zero open tickets that morning.

## The options

**1. Finish NilPy.** The only remaining finite goal of any size. N took 628 of
1751 track-tagged commits in the last 30 days (38%, nearly 2x the next lane) and
holds 53% of every remaining open bug. Clearing it takes the biggest consumer of
effort off the board and drops total open bugs to ~15. Downside: it is the lane
you have already spent two months on, and several of its bugs need pins
(`compiler/builtin`), which serialise against everyone.

**2. Open an esoteric frontend.** `feature-esoteric-ada` and
`feature-esoteric-cobol` are already filed in `experimental/`, unranked by
design. Near-ideal parallel work: own files, own gate, zero collision with A/P/N,
and it directly exercises the IR-as-substrate thesis — a new frontend landing
cheaply is the strongest evidence that thesis is true. Downside: adds surface
while NilPy is unfinished.

**3. Push the corpora.** rtl-generics rung 3 is mid-climb (P), quickjs (C),
third-party libraries (N). Highest measured bug-discovery rate of anything we
do — yesterday it produced 6 fixes in an afternoon — and it parallelises by
construction, since each corpus generates bugs in a different lane. Downside: it
GROWS the bug count on purpose, so it will not feel like progress on a burn-down
view.

## Recommendation

**3, with 1 as the second lane.** Corpus work is the only activity that reliably
finds unknown defects, and the composition numbers say discovery is now worth
more than queue-draining. Pairing it with NilPy gives the finite goal somewhere
to land. Option 2 is the one to take when you want the project to be FUN rather
than thorough — which is a legitimate reason and the reason those tickets exist,
so this is a preference question, not a numbers question.

## What changes on each answer

- **(1)** frank2 stays on N and I schedule its pins in batches.
- **(2)** a new checkout gets the frontend; I hold A for the shared-internals
  tickets it will generate.
- **(3)** frank3 or a new session takes a corpus; expect the open-bug count to
  RISE and that is the intended outcome, not a regression.

## Ruling (human, 2026-08-18)

**Option 3 with 1 as the second lane — as recommended. The two are ONE theme, not
two.** The overnight measurement is what settled it: finish-NilPy and push-the-corpora
turned out not to be competing choices, because the corpus that generates N's
remaining work IS third-party-libraries-as-targets. Driving corpora forward and
finishing NilPy are the same activity viewed from two ends.

So this resolves as a **confirmation**, not a fork — which is why it sat at p70 with
nothing blocked on it.

Operative consequences, in the ticket rather than in chat:

- **Expect the open-bug count to RISE, and that is the intended outcome.** Corpus work
  is measured as the highest bug-discovery activity we have (6 fixes in one afternoon).
  A burn-down view will read this week as regression. It is not.
- **Discovery now outranks queue-draining** on the composition numbers (146 features vs
  32 bugs). A corpus finding beats a mid-prio queue item for the same tokens.
- **Option 2 (esoteric frontends) is explicitly NOT this week.** Left in
  `experimental/`, unranked, as designed. It stays available as the fun-rather-than-
  thorough choice; this ruling does not reject it, it defers it.
- Staffing this ruling implies: frank2 → N, frank3 stays B. Set the same day.

**Filing note (the failure mode this ticket must avoid):** a resolved `decide-*` that
is never re-filed into its lane becomes invisible to `ready`/`next` and the work gets
rediscovered later, sometimes with an approach the decision already rejected. Nothing
new needs filing here — the corpus tickets already exist and are ranked
(`feature-pascal-corpus-generics`, `feature-pascal-corpus-oop`,
`feature-c-csmith-differential-fuzzing`, `feature-nilpy-thirdparty-libraries-as-targets`,
quickjs). What this ruling changes is their PRIORITY relative to queue-drain work, so
the theme lands as ranking, not as prose here.

## Log
- 2026-08-18 — decided, commit PENDING-COMMIT.
