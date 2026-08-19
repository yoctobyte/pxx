---
track: T
prio: 30
type: chore
blocked-by: []
commit: e3eec52dd
claimed-by: plexus-T
status: done
---

# Detect citations that name a bookkeeping commit, never repair them

Requested 2026-08-19 by the coordinator, after measuring the historical damage
from `sync.sh`'s old `-S` sha lookup
([[bug-t-sync-fills-one-spelling-of-pending-commit-and-check-counts-two]]).
**A DETECTOR, explicitly not a repairer** — that was the user's approval and it
is also the right call: a confidently wrong citation is worse than a missing one
because it reads as authoritative, and ~82% of bad citations *look* fixable by
matching against `git log`
([[bug-t-resolve-cites-a-sha-the-rebase-then-rewrites]]).

## Shipped

`tools/progress.sh check --strict` gains `WARN-BOOKKEEPING-CITATION`, two arms,
**12 findings** today:

- **11 — the citation names a WATCHER PUBLISH.** `tstate(borg): opt d606c7... done`,
  `tstate(borg): 163ffea562fa GREEN (full) FIXED:test-smoke#11`. That process
  never fixed anything, so the citation names an *observation* of the fix rather
  than the fix. Several are auto-closed regression stubs, where it is arguably
  the honest record — the message says so and leaves the call to the reader.
- **1 — the citation is SELF-REFERENTIAL:** the ticket cites the commit whose
  entire content is resolving that same ticket.
  `bug-a-virtual-method-int64-in-and-out-32bit` cites `fd99c8836`
  *"docs(progress): resolve bug-a-virtual-method-int64-in-and-out-32bit"*, where
  the fix is `77d32b346` *"fix(A): 32-bit virtual calls dropped the high half of
  a 64-bit argument"*. This arm finds **exactly that one** across all 1424 cited
  shas — the single instance anybody has independently verified.

Each line carries the cited SUBJECT, because the subject is what a reader judges
on, and says plainly that the finding may be correct: a duplicate close, or a
ticket already fixed elsewhere, has no fix commit and the bookkeeping commit
genuinely *is* its resolution.

Strict-only, so it surfaces during an audit rather than on every run. Costs
nothing: subjects now come from the same single `git log` pass that already
builds the dead-sha index — 1424 individual `git log -1` calls would have cost
17s, the shared pass costs ~0.2s and the whole strict check runs in 6.5s.

## Two measurements that did NOT become the check, and why

Both were tried and rejected on noise, which is the failure mode this repo keeps
recording — a guard that reports 65 things, most of them fine, gets muted.

| candidate rule | findings | verdict |
| --- | --- | --- |
| any `tstate(...)` subject | **65** | rejected. `tstate(A): close aarch64 large-double formatting` is an AGENT closing a ticket and is a perfectly good citation. Narrowed to the watcher's rigid publish format (`tstate(<host>): <12-hex>` or `opt\|slow\|bench\|pin`) |
| the cited commit touches ONLY `devdocs/` | **199** (151 from bug/regression tickets) | rejected. That is the population where a wrong citation is POSSIBLE, not where one exists — it is simply every ticket whose resolve landed separately from its fix |

**The 199 figure is worth keeping and worth not misreporting.** It is not
"199 wrong citations". Neither was the coordinator's 27 — of which many were
legitimate duplicate/already-fixed closes, as they caught themselves before
reporting it. Nothing in a sha distinguishes "the docs commit IS the resolution"
from "the fix landed separately", which is exactly why this reports and does not
repair.

## Known gap, stated rather than hidden

Arm 2 catches the self-referential shape only. A ticket resolved by a docs-only
commit whose subject does NOT name the ticket, where the fix landed separately,
is **not detected** — it is inside the 199 and indistinguishable from a
legitimate duplicate-close. Widening to catch it means accepting ~151 findings
nobody can triage cheaply, and that trade is worse than the gap.

## Gate

`tools/progress.sh check` (non-strict) output unchanged; `--strict` gains 12
lines. `tools/sync_pending_commit_devtest.py` green (10 cases), whole
`make tools-devtest` family green (38 guards).

## Log
- 2026-08-19 — resolved, commit e3eec52dd.
