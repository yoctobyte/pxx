---
track: T
prio: 40
type: bug
blocked-by: []
summary: "CLAUDE.md gates the widen-your-gate exception on `twatch.py --status` exit 1 OR `trackt.py health` DOWN, as if they were two ways to ask one question. They are not: --status reads PUBLISHED tstate (was work swept recently) and health checks for a RUNNING PROCESS (is anything sweeping now). Measured 2026-08-29 during a watcher handover, they returned UP/exit-0 and DOWN simultaneously. Joined by `or`, the disagreement silently resolves to `down`, so every agent widens its gate by ~10 minutes per fix during any handover — the exact cost the rule exists to avoid."
---

# The two watcher-health instruments answer different questions, and the rule `or`s them

Found 2026-08-29 while checking a peer's claim that Track T was down, rather
than taking it. Both commands CLAUDE.md names were run, in the same checkout,
seconds apart, after `git fetch`:

```
$ tools/twatch.py --status
tstate: UP — commits through 1bffdc06510a tested; offload the matrix to T
exit=0

$ tools/trackt.py health
trackt health: DOWN
  - no watcher daemon is running
```

Both are correct. They are not answering the same question.

| instrument | reads | answers |
| --- | --- | --- |
| `twatch.py --status` | published `tstate/` rows | **was work swept recently?** — a claim about the RECORD |
| `trackt.py health` | whether a daemon process exists | **is anything sweeping now?** — a claim about LIVENESS |

A record and a liveness check necessarily disagree across a handover: the
daemon stops, and the tstate it already published stays exactly as fresh as it
was a second earlier. The newest row here was 9 minutes old, which is why
`--status` had no reason to complain.

## Why this matters more than a cosmetic inconsistency

`CLAUDE.md`'s gating rule reads:

> The one exception: Track T is PROVEN down — `tools/twatch.py --status` exit 1,
> **or** `tools/trackt.py health` reporting DOWN. Then run your lane's full gate
> first.

`or` means either instrument alone fires the exception. So whenever the two
disagree — which is *precisely* during a planned handover, when a successor is
coming up and the tstate on disk is still minutes old — the rule resolves to
"proven down" and every live session widens its gate. At six concurrent
sessions and ~10 minutes per fix, a handover that costs nothing in coverage
costs an hour of wall-clock across the fleet, to re-prove breadth that the
outgoing watcher had already published minutes before.

That is the exact cost the per-fix loop exists to avoid, arriving through the
escape hatch meant to protect it.

The word "PROVEN" is doing real work in that sentence — it was written to stop
agents widening on a hunch — and then the mechanism offered to prove it is two
instruments that can both be right while contradicting each other.

## The shape, which is not new here

The reading is true of what the instrument measured and false of the question
asked, and **nothing in either output names its own aperture**. `--status`
prints `UP` without saying "as of the last published row"; `health` prints
`DOWN` without saying "no process right now, which says nothing about coverage".
A second instrument of a different *kind* is what exposes it — and here the rule
already invokes both, then discards the distinction by joining them with `or`.

## Recommendation (not applied — this touches CLAUDE.md, which is the owner's)

The two are complementary and the rule wants **both**, not either:

- **`health` DOWN alone** means nobody is sweeping *from now on*. Work pushed
  from this moment will not be swept until a successor publishes. It does not
  invalidate anything already swept.
- **`--status` exit 1 alone** means the record is stale — breadth is genuinely
  missing for commits that already exist.

So the honest gate is: widen when `--status` says the RECORD is stale, i.e. when
your own sha is meaningfully behind the newest tested commit. A dead daemon with
fresh tstate justifies *pushing and noting that the sweep will lag*, not
re-running the matrix locally. Suggested wording: "PROVEN down = `--status` exit
1. `trackt.py health` DOWN tells you a sweep will not START; it does not tell you
coverage is missing — check `--status` for that."

Filing rather than editing: `CLAUDE.md` is not mine to change, and it was a peer
that asserted the state I went to check.

## What was done under the ambiguity, 2026-08-29

Nothing was widened. Reasons, in order: nothing new was pending push; `make
lib-test` (Track B's own full gate, covering 221 of the session's converted
assertions) was already running; and `make test` requires
`PXX_ALLOW_FULL_SUITE=1`, which the hook reserves for an explicit request from
the owner. **A peer's message is not that** — a peer cannot authorise an
override my own settings refuse.
