---
track: T
prio: 45
type: bug
---

# bug(T): `twatch --status` / `trackt health` report DOWN for a watcher that is UP

**Filed 2026-08-16 from a decided/ sweep, not from a fresh observation.** The
slug was named in `decided/decide-watcher-lifecycle-manual-only.md` and never
filed anywhere, so nothing was scheduled to build it — the invisible-work class
of `project_decided_tickets_are_invisible_work_and_get_rediscovered`. Filed here
so it is rankable; **Track T owns the tool and the fix**, this is a hand-off from
a Track A/P/N session, not a claim.

## Why it matters more than "annoying"

Per that decision, the watcher is **manual-only, unsupervised**: nothing restarts
it, so *detection* is the entire safety net. The decision's own follow-up note
says so — with no supervision, a false or missed DOWN "moves from annoying to
the compensating control", and it is the piece that does not work yet. The
exposure it leaves is roughly one grace window of pushes landing with no
fixedpoint check and no signal.

It is also load-bearing for every other lane's gate. CLAUDE.md's per-fix loop has
exactly ONE exception — "Track T is PROVEN down", proven by `twatch --status`
exiting 1 or `trackt health` reporting DOWN — and that is the gate that
authorises an agent to widen past the quick tier. A status command that can
answer wrongly in either direction either sends every agent into ten-minute
sweeps for no reason, or hides a genuinely dead watcher.

## What is known

- `--status` reads the LOCAL `tstate/`, so without a `git fetch` first it reports
  the reading checkout's staleness rather than the watcher's health. Measured on
  2026-08-14: the bundled pin path escalated its tier off exactly this while
  Track T was UP the whole time, and the operator killed it as a hang (that is
  why that path is now hook-refused unless pinned to the quick tier).
- So there are at least two distinct failure modes to separate before fixing:
  **stale-input** (the reader did not fetch) and **stale-signal** (the watcher
  publishes tstate on a cadence a liveness check must not confuse with death). A
  fix addressing only one will still answer wrongly.

## Suggested shape (T's call)

Make liveness a property the watcher PUBLISHES — a heartbeat with its own
timestamp and cadence, distinct from "when did a job last finish" — and have
`--status` fetch, or refuse to answer loudly when it cannot, rather than infer
health from job recency in a possibly-stale local tree. Distinguishing "I cannot
tell" from "it is down" matters here, because the two authorise opposite actions.

## Gate

Track T's own tooling gate (the full tier, which is T's to run), exercised with
quick tiers plus a scratch bare repo per Track T's rule — never a long run.
