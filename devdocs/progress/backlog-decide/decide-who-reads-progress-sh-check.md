---
slug: decide-who-reads-progress-sh-check
track: U
type: decide
prio: 55
status: open
blocked-by: []
summary: "`tools/progress.sh check` works, reports correctly, and has no reader. It had been printing a p60 as invisible-to-the-ranker for days (STALE-EDGE-HIDDEN + BLOCKED-BY-REJECTED on perf-p-parsefactorcore) and nothing acted. The fork is WHO reads it, and it splits: the MECHANICAL classes (a ticket hidden from ready/next by a blocker that is closed, rejected or nonexistent) need no judgement and could be wired into ready/next; the JUDGEMENT classes (STALE-PARK, NEAR-DUP, DEAD-COMMIT, PROSE-EDGE) cannot be automated at all, because STALE-PARK matches SLUGS not QUESTIONS. Recommendation: wire the mechanical subset, leave the rest on-demand, and give STALE-PARK-HELD a router. Not filed as a Track T defect: the tool is not broken."
---

# Who reads `tools/progress.sh check`?

Surfaced by frankH and frank-coordinator, 2026-09-01. **The tool is not broken
and does not need writing.** It needs a reader, which is a workflow question.

## What it cost, concretely

`perf-p-parsefactorcore-walks-a-92-arm-name-chain-per-factor` — **p60** — sat in
`blocked/` with its only blocker rejected. `ready`/`next` never scan `blocked/`,
so **no path could ever surface it**, and `check` had been saying so in two
independent classes the whole time. Repaired 2026-09-01.

frankH found the family the same way: `bug-b-tlist-has-no-list-property` had
been unblocked for days behind a `blocked-by` naming a slug that no longer
existed — the Track A defect had been **renamed** and closed.

Also standing right now: 4 `STALE-PARK-HELD` addressed to frankA whose
instruction is literally *"tell the holder"*, with nothing doing the telling.

## The fork — and it is not one decision, it is two

**Mechanical classes.** `STALE-EDGE-HIDDEN`, `BLOCKED-BY-REJECTED`, and a
`blocked-by` naming a nonexistent slug. In every case a ticket is hidden from
the ranker **for a reason that is provably not real**, and confirming it takes
no judgement — the blocker is closed, rejected, or absent. This is the ranker
being wrong, not a workflow preference.

**Judgement classes.** `STALE-PARK`, `NEAR-DUP`, `DEAD-COMMIT`, `PROSE-EDGE`.
These **cannot** be swept, and `check`'s own output says why: *a STALE-PARK hit
matches SLUGS, not questions — a blocker that settled the OPPOSITE question
reads exactly like one that settled yours.* Auto-resolving these would
manufacture wrong closures at scale.

## Recommendation

1. **Wire the mechanical subset into `ready`/`next`** so ranked work cannot be
   hidden by a dead edge. A p60 invisible to every path is a ranker defect.
2. **Leave the judgement classes on-demand.** Accept that they age. The
   alternative is worse than aging.
3. **Give `STALE-PARK-HELD` a router.** Its instruction already names its
   reader — the holder — and the coordinator's relay is the mechanism that
   exists. It relayed frankA's four on 2026-09-01.

## What needs the owner rather than a default

Option (a) as originally posed — **run `check` in the tstate cycle and auto-file
what it finds** — is the one this ticket will not take on a default. It spends
Track T's machine, and *"widening your own gate spends the machine that produces
the 8"* applies to the ranker's hygiene as much as to a test tier. It would also
auto-file the judgement classes, which is the one thing the caveat above forbids.

**This is the fourth item in one evening where the information existed and the
reader did not** (frank-coordinator's count): the auto-filed regression heading,
the tstate detail block, `trackt.py health` answering about the wrong host, and
this. That pattern is the argument for (1); it is not an argument for (a).
