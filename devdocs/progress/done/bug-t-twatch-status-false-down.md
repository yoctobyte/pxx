---
track: T
prio: 45
type: bug
status: done
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

## 2026-08-17 — FIXED: the reader now fetches, and "cannot tell" is its own answer

Both failure modes the ticket asked to separate, addressed separately.

### stale-input — `--status` fetches

Every earlier false DOWN in this function's history (2026-07-14, 07-20, 08-01)
was the same shape: the verdict was computed from a ref the reader had not
refreshed. Preferring `origin/master` over `HEAD` fixed the worse half; it
cannot fix a *stale* `origin/master`. `--status` now refreshes it first.
`--no-fetch` opts out and makes any DOWN unproven (below).

`trackt health` needed no change — it already fetches with `check=True` before
extracting the tstate blobs, and falls back to the no-`tdir` path when it
cannot, which is now the path that fetches for itself. So an explicit `tdir` is
the caller's assertion of freshness, and that assertion is earned.

### stale-signal — three states, not two

> *"Distinguishing 'I cannot tell' from 'it is down' matters here, because the
> two authorise opposite actions."*

| exit | meaning | authorises |
| --- | --- | --- |
| 0 | UP | offload the matrix to T |
| 1 | **PROVEN** down | the CLAUDE.md exception: widen past the quick tier |
| 2 | cannot tell | run your own gate — but do **not** cite it as proof |

A DOWN computed from data this checkout never fetched is equally consistent
with a healthy watcher and a stale reader, so it is not proof of anything.
Returning 1 for it is exactly how a false DOWN sends every agent into
ten-minute sweeps.

**Backwards compatible in the safe direction:** a caller testing truthiness
(`if twatch --status; then offload; else gate; fi`) treats 2 like 1 and runs its
own gate. When T's health is unknown, covering yourself is correct — the change
only removes the *claim* of proof, never the caution.

`no watcher state at all` + could-not-fetch is deliberately routed to UNKNOWN
rather than DOWN: in an unfetched checkout that is overwhelmingly a reader
problem (fresh clone, wrong path), not a dead fleet.

### A bug in the fix, worth recording because it is this repo's recurring shape

First cut set `fetched = True` and cleared it only when the fetch *threw* — so
`--no-fetch` reported an **uncaveated UP**, the flag silently asserting the
freshness it exists to decline. `no exception occurred` is a true statement and
is not the question. Now `fetched` means "origin/master is known-fresh", which
is what every consumer of it actually asks. Same family as
`bug-p-a-class-method-does-not-shadow-a-builtin` (keyed on the token, not the
destination type) and the `pgrep` case in `track-t.md`.

### Verified

| case | exit |
| --- | --- |
| live repo, fetches | 0 UP |
| live repo `--no-fetch` | 0 UP, line carries `[UNFETCHED — ...]` |
| repo with no remote | **2 UNKNOWN**, and says the fetch failed |
| `trackt health` (tdir path) | 0, unchanged |

### Not done

The ticket's suggested **published heartbeat with its own cadence** is not
built. Its motivating case — a live watcher on a quiet repo looking dead — is
explicitly declared not to matter by `status()`'s own contract ("a quiet watcher
on a quiet repo is indistinguishable from a dead one — and it doesn't matter"),
and publishing a beat every idle cycle would add commit traffic to a repo where
tstate churn is already the largest single source. The grace window remains a
fixed 45 min rather than derived from the daemon's interval; deriving it is the
cheap half of that idea and is worth doing if a wrong grace is ever observed.

## Log
- 2026-08-17 — resolved, commit PENDING-COMMIT.
