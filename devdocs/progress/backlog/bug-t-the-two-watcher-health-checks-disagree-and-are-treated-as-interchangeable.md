---
track: T
prio: 40
type: bug
blocked-by: []
summary: "CLAUDE.md gates the widen-your-gate exception on `twatch.py --status` exit 1 OR `trackt.py health` DOWN, as if they were two ways to ask one question. They are not: --status reads PUBLISHED tstate (was work swept recently) and health checks for a RUNNING PROCESS (is anything sweeping now). Joined by `or`, the disagreement resolves silently to `down`. NO LONGER TRANSIENT: since Track T moved to `seven` (2026-08-29, recorded at the bottom of this ticket), `health` on plexus is STRUCTURALLY INCAPABLE of returning UP -- `daemon_pid` scans the LOCAL /proc and `is_daemon` requires a local argv of `<python> .../twatch.py --clone <clone>`, which a watcher on another host can never satisfy. Re-measured 2026-08-31 with T demonstrably sweeping (report 7.5 min old): `--status` exit 0, `health` DOWN. So the documented exception was PERMANENTLY ARMED for every dev agent, not open during handovers. HALF FIXED 2026-08-31 by frankT (see the addendum): `trackt.py health` now answers REMOTE / exit 0 on a box with no local daemon whose PUBLISHED archive is fresh, and still DOWN / exit 2 when it is stale or absent -- so the command can no longer arm the exception structurally, and a DOWN from it means something again. WHAT REMAINS IS THE DOC HALF AND IT IS NOT MINE TO TAKE: CLAUDE.md still joins the two instruments with `or`, which is the actual subject of this ticket. They answer different questions and the `or` still resolves a disagreement silently to `down`. That edit is the owner's."
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

## Reassigned to `seven` with Track T, 2026-08-29

Track T moved off plexus entirely — both faces — on the owner's topology call,
relayed by the coordinator. This ticket was mine under the short-lived
provenance split and goes with the lane rather than being closed.

**A second, independent instance, relayed by the coordinator from `seven` and
NOT measured by me** — recorded here so the reassignment does not lose it.
`seven` reportedly spent a stretch of 2026-08-29 in exactly this state:
`--status` reading UP from plexus's *published* record while no daemon was
running anywhere. Attribution matters because the whole point of this ticket is
that a record can outlive the process that wrote it; a second-hand report is a
record too, and whoever picks this up should re-measure on `seven` rather than
inherit the claim.

That instance is the stronger evidence, and it sharpens the diagnosis: my
original was a handover on ONE box, where "stale by 9 minutes" is arguably
within tolerance. Seven's is cross-box — a published record from a DIFFERENT
machine answering UP for a lane with no live sweeper anywhere. The record's
freshness and the fleet's liveness are not merely different questions, they can
be about different hosts.

The fix is unchanged and does not need my presence: the two instruments should
report as a pair — freshness AND liveness, both named — rather than being
`or`ed into one boolean where the disagreement resolves silently to `down`.
Left takeable in `backlog/`, unclaimed.

## Re-measured 2026-08-31 by frankA (Track A): the disagreement is now PERMANENT, not a handover window

I hit this from the other end — chasing a parked ticket whose resume condition
was "the next full sweep on seven answers this" — and read `health`'s DOWN as
proof Track T had stopped. It has not. **Track T was sweeping the whole time**,
and I was ~1 command from relaying a fleet-wide false alarm.

The artefact settles it, and it is the instrument neither command is:

```
now                        2026-08-31T02:31:11Z
newest report              20260831T022353Z-bebac33-seven.md   (7.5 min old)
last 5 tstate commits      04:23 / 04:21 / 04:12 / 04:09 / 03:59 local, all "tstate(seven)"
                           full and native tiers alternating

tools/twatch.py --status   exit 0          <- correct
tools/trackt.py health     DOWN            <- and it CANNOT say anything else
```

### Why this is structural, not a window

`trackt.py:130-133` falls back to `for p in os.listdir("/proc")`, and
`is_daemon` requires `argv[1].endswith("twatch.py")` **and** `clone in argv` —
read from `/proc/<pid>/cmdline` on **this** box. Track T runs on `seven`. A
process on another host has no entry in plexus's process table, so the check
cannot match, ever.

Verified it is not merely mis-invoked: `health` returns DOWN both with no
argument and with `--clone /home/neo/trackt-watch` (the watcher clone that still
exists here). The only local process is `twatch_web.py`, the web face, which
`is_daemon` correctly rejects — `"twatch_web.py".endswith("twatch.py")` is False.

Checked and NOT a hazard, so nobody re-derives it: `WATCH_REL` is
`.testmgr/watch.json`, which is **not** published to the repo (the published
files are `devdocs/progress/tstate/*.json`). So `health` never reads a *remote*
pid and tests it against the *local* process table. That failure mode does not
exist here.

### What changes

The body above says the two disagree "*precisely* during a planned handover" and
prices it as "an hour of wall-clock across the fleet" per handover. On the
current topology that is an **understatement of kind, not of degree**: there is
no window, because the condition never closes. Every agent on plexus who types
the command CLAUDE.md names gets DOWN, today, and is licensed by CLAUDE.md to
run `testmgr --tier full` — the exact widening the hook and the whole gating
section exist to prevent.

**The cause is already written at the bottom of this ticket.** The
"Reassigned to `seven`" note records the move that makes the check permanently
false, and the diagnosis sits eighty lines above it; nobody joined the two. That
is the ticket's own subject matter — a reading true of what the instrument
measured and false of the question asked — reappearing as two true sections of
one page that were never read against each other.

**So prio 40 is priced for the transient reading and is now too low** — T's call,
not mine. The one-line doc fix (drop the `or` clause, keep `--status` as the
proof) is already recommended above and needs no new analysis; what is new is
that it is not a tidy-up.

*Track T's tool — `tools/trackt.py` NOT edited. Measurement added only.*

---

## HALF FIXED 2026-08-31 by frankT — the TOOL, not the doc

frankA measured the structural impossibility (14ecbb933) and correctly did not
touch `trackt.py`. I own it, so I did: **`tools/trackt.py` `health` now has a
third verdict.**

`health_check` opened with `if not pid: return "DOWN"` where `pid` comes from
`daemon_pid`, which falls back to scanning the **local** `/proc`. A watcher on
another host has no entry there, so on any non-watcher box that branch was the
only reachable one. It now calls `no_local_daemon()`, which asks the question
the caller actually has — *is Track T sweeping?* — of the instrument that can
answer it from here, the published archive:

| local daemon | newest published row | verdict | exit |
| --- | --- | --- | ---: |
| running | — | OK / DEGRADED / DOWN as before | 0 / 0 / 2 |
| none | ≤ 1h old | **REMOTE**, naming the host, tier, sha and age | **0** |
| none | > 1h old | DOWN, naming the age | 2 |
| none | no rows at all | DOWN | 2 |

**The threshold is measured, not chosen.** Over the 259 rows published in the
preceding 24h the gap between consecutive tstate rows had median 205s, p90 664s,
p99 1151s and a **maximum of 1641s (27min)**. One hour is 2.2x the observed
maximum and would have produced **zero** false DOWNs across that window. The
asymmetry is deliberate and is the whole point: a false DOWN costs every agent
on the box ten minutes of full gate; a true DOWN noticed an hour late costs
nothing, because the sampler was already not running.

**`tools/trackt_remote_health_devtest.py` leads with the case it must REJECT**,
because a check that has only swapped which single answer it gives is not
better than the one it replaced: a stale archive with no local daemon must still
come back DOWN with exit 2, and an empty archive likewise — absence of evidence
is not a green. Only then does it assert the accept side, plus that a **RED**
newest row still yields REMOTE (the question is whether T is *sweeping*, not
whether it is *green*), that the newest row across hosts wins, and both sides of
the threshold. Auto-enrolled: `tools-devtest` globs `tools/*devtest*.py`.

Live on plexus, with seven sweeping:

```
trackt health: REMOTE
  - no watcher daemon on plexus -- Track T runs elsewhere, which is not a fault
    and is NOT proof it is down
  - newest published verdict: host=seven tier=native RED at bebac33366f5, 11min ago
exit=0
```

**This does not close the ticket.** The subject is the `or` in CLAUDE.md joining
two instruments that answer different questions, and that text is unchanged. What
the fix does is remove the *structural* failure underneath it: `health` DOWN is
now evidence again rather than a constant. The two commands still answer
different questions and should not be `or`ed, and **the doc edit is the owner's
call, not a peer's and not mine.**
