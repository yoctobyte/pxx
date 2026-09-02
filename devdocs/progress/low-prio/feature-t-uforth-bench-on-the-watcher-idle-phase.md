---
status: low-prio
track: T
prio: 25
type: feature
blocked-by: []
summary: "tools/uforth_bench.py is standalone + a make target, so uforth rows only exist when a human types it. Hang it off the watcher's idle bench phase so rows land per-sha automatically — which is also the only way to get the quiet-box baseline the harness has never had, and the instrument for the open slow-creep question."
---

# Run the uforth bench from the watcher's idle phase

- **Type:** feature (bench infrastructure) — **Track T**
- **Opened:** 2026-08-17
- **Split out of** [[feature-t-uforth-benchmark-harness]], which listed this as
  a follow-up "filed, not blocking" — and it was never filed. Filing it so it is
  rankable, per the invisible-work rule.

## Why

The harness works and its row schema already matches `bench.tsv`. What it has
never had is a **quiet box**: every number recorded for it — the 2026-07-22
originals and the 2026-08-17 re-run — was taken while a full tier or a second
dev session was running. The harness's own follow-up list says "re-baseline when
idle", and nobody can reliably catch idle by hand.

The watcher already has an idle `bench` phase that runs only when the box is
quiet, with a co-tenancy check that refuses to bench under load
([[bug-t-bench-timings-recorded-under-co-tenancy]]). Hanging uforth off it makes
the quiet baseline a property of the schedule rather than of someone's timing.

## It is also the instrument for an open question

[[bug-t-a-timeout-bisects-to-an-innocent-commit]] left one residual that
argument cannot settle: **is there slow-creep underneath the co-tenancy noise?**
A 2x swing from co-tenancy hides anything smaller, and both measurements
available came from a box where one of the measuring parties WAS the contention.

Rows accumulated on undisturbed runs are the only way that gets answered. This
ticket is what produces them.

## Shape

- Emit into `bench.tsv` (schema already matches; the uforth sha is column 7).
- Skip cleanly when the uforth checkout, python3, or a usable pxx is absent —
  the harness already does; keep that behaviour when driven by the daemon.
- Bounded: the default (non-`--full`) set is ~1 minute of work at `--runs 1`;
  the daemon's idle phase is the right place to afford more runs.
- **Must use the CURRENT compiler**, not the pin: the pinned stable cannot lex
  uforth's char-code literals. This is a real constraint, not an oversight.

## Gate

A uforth row lands per-sha without anyone typing a command, and the rows carry
a task clock that shows the box was actually quiet when they were taken.

## Deprioritised 2026-09-02 — the Track T tooling backlog was cut as a pile

**This ticket is not being called wrong.** It was moved as part of a pile, not
judged individually, and nothing here disputes its finding.

Owner decision. 73 of the 74 open `track: T` tickets were filed between
2026-08-31 and 2026-09-02, 58 on one day. The pile was too large to work through
and returned almost nothing, and a ticket nobody will fix does not sit neutrally
— it stays in the ranker forever at zero value, which is the argument CLAUDE.md
already makes for a terminal folder over a low prio.

Four were kept in the ranker on a purely structural test — an active umbrella or
a hard `blocked-by:` edge from live work:
`umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**Kept, not deleted, for two reasons:** so the finding is not rediscovered and
refiled from scratch by the next agent who trips over it, and so it can be pulled
back if what it touches becomes load-bearing.

**To revive it:** move it to the owning lane's backlog, set `status: backlog`,
and say in the ticket WHAT CHANGED to make it matter now. Restoring it because it
reads well is how the pile comes back.
