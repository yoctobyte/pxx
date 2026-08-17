---
track: T
prio: 35
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
