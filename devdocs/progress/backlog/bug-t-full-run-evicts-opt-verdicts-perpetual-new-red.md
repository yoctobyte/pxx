---
summary: DUPLICATE of bug-t-full-tier-wipes-other-tiers-job-status — "a full run replaces the whole job map and evicts opt-tier verdicts, so every opt-only red re-reports as NEW-RED forever"
type: bug
track: T
prio: 75
---

# A full run evicts opt-tier verdicts, manufacturing NEW-RED every cycle

- **Type:** bug (Track T — `tools/twatch.py`, the NEW-RED signal itself)
- **Found:** 2026-08-01 overnight on xeon, from a repeating `optdiff` report.
- **This is the root cause of the long-suspected "phantom NEW-REDs".**

## Observed

`optdiff#shard5/6` is genuinely red (see
[[bug-c-wide-string-literal-narrow-in-value-context]]). It is stored in
`xeon.json` as `fail`. Yet every subsequent opt run reports it as **NEW-RED**,
not STILL-RED:

```
21:23 full RED   (full tier contains no optdiff jobs)
21:33 opt  RED   NEW-RED optdiff#shard5/6      <- genuine, first sighting
21:49 full RED   (evicts optdiff from the map)
22:00 opt  RED   NEW-RED optdiff#shard5/6      <- phantom, identical red
```

Indefinitely, once per opt cycle, for as long as the red exists.

## Mechanism

Two lines, and they are individually reasonable:

```python
# twatch.py — publish
if full:
    st["jobs"] = now                        # REPLACE the whole map
else:
    st["jobs"] = dict(st["jobs"], **now)    # merge

# twatch.py — diff_jobs
prev_jobs.get(n, "pass")                    # an ABSENT job counted as passing
```

and one fact about tier composition:

```python
# testmgr.py — the optdiff jobs exist ONLY in the opt tier
if tier == "opt":
    for i in range(OPT_SHARDS): ...
```

So a **full** run replaces the map with a job set that by construction contains
no opt jobs — evicting their verdicts. The next opt run looks them up, finds
them absent, and `prev_jobs.get(n, "pass")` reports them as having been green.
Red → "was pass" → **NEW-RED**.

The replace was right in intent (drop jobs that no longer exist in the suite)
but wrong in scope: **a run may only evict jobs it was capable of running.** A
full run cannot speak for the opt tier.

## Why this matters more than the noise suggests

The report contract says *"NEW-RED **vs the previously tested SHA** is the
signal, not raw fail counts."* This defect corrupts precisely that signal, and
it corrupts it in the expensive direction: it invents transitions. An agent
reading tstate sees a job "newly break" at a sha whose diff cannot explain it —
which is exactly the pattern that taught everyone to distrust tstate.

It also inverts the meaning of a green: a job absent from the map is silently
treated as passing, so eviction reads as success.

Blast radius today is bounded — `optdiff#*` and `test-opt#*` are the only
tier-exclusive jobs, and autoticket's dedupe held (two NEW-RED reports produced
**one** ticket, verified). The signal is wrong; the board is not polluted.

## Fix

Evict by **coverage**, not wholesale. A run replaces the verdicts for jobs it
could have run and leaves every other tier's verdicts alone:

```python
if full:
    covered = {k for k in st["jobs"] if tier_covers(this_tier, k)}
    st["jobs"] = {k: v for k, v in st["jobs"].items() if k not in covered}
    st["jobs"].update(now)
```

`tier_covers` needs a per-job record of which tier last set it — cheapest is a
parallel `st["job_tier"] = {key: tier}` written alongside, or reusing the job's
`cls` from the report json (check what `Job("optdiff", ...)` actually sets `cls`
to before relying on it). Either way the rule is the same: **keys last set by a
tier this run did not cover are carried forward untouched.**

Worth fixing in the same pass — `prev_jobs.get(n, "pass")` should not default to
green. An unknown job is *unknown*, not passing; treat it as "no baseline" and
report it as a first sighting rather than a transition. That is also the
mechanism behind [[task-t-suppress-autoticket-until-host-baselined]], where an
empty map made every red on a new host look new.

## Verify with

Two runs and no code change in between should produce one NEW-RED and then a
STILL-RED:

```sh
tools/testmgr.py --tier opt  --job 'optdiff#shard5/6'
tools/testmgr.py --tier full --job 'test-smoke#00'
tools/testmgr.py --tier opt  --job 'optdiff#shard5/6'   # must NOT say NEW-RED
```

Test against a scratch bare repo with quick tiers, never a live long run.


---

## DUPLICATE — superseded by [[bug-t-full-tier-wipes-other-tiers-job-status]]

Filed by `claude@xeon` 12 minutes after `claude@borg` filed the same bug
from the same tstate signal. The push is the arbiter and theirs landed
first, so **that ticket is canonical**; this one is kept for the detail
below and should not be worked independently.

A fix is already **landed but not deployed**: `5f1596bde` adds
`covered_tiers()` plus a `job_tier` map, so a run may only evict jobs it
was capable of running. Verified against the observed opt/full/opt/full/opt
sequence with the daemon's own unpatched copy as the negative control —
NEW-RED on runs 1, 3, 5 before; run 1 only after — and separately that a
job genuinely removed from the full tier is still evicted. `twatch.py` is
loaded once at daemon start, so it takes effect on the next deliberate
restart.
