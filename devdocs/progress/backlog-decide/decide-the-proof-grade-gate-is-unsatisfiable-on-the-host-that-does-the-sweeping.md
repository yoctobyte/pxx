---
track: U
prio: 55
type: decide
blocked-by: []
summary: "CLAUDE.md's -O3 promotion gate defines proof as a full run with `skip_holes == 0`. Measured 2026-08-31 over seven's whole archive: 121 full-tier runs, 120 with skip_holes=1 and one with 2 — NONE at 0, ever. The hole is a permanently unrunnable rdrand job, and it is structural: seven is dual E5645 (Westmere, no RDRAND) while plexus has it. Since Track T moved to seven on 2026-08-29, the gate as written can never be met, so NO -O3 pass can ever be promoted. Needs a ruling on what proof-grade means in the presence of a permanent host hole; recommendation is an enumerated per-host allowlist so a NEW hole still fails. PREMISE PARTLY OVERTAKEN BY EVENTS 2026-09-16: the sweeping host is BORG now, not seven (plexus retired to borg 2026-09-11), and borg SATISFIES the literal gate -- 114 full-tier runs since the handover, every one at skip_holes=0, and ZERO borg full runs at skip_holes>0, ever. So the gate is no longer unsatisfiable where the sweeping happens and NO promotion is blocked by it today. The fork is NOT closed: it was always about what proof-grade MEANS in the presence of a structural host hole, and that question survives a host move -- it just stops being urgent. Re-read option 1 in this light: it costs nothing today, which it did not when this was written."
---

# A gate that cannot pass is not a gate either

CLAUDE.md rules the `-O3` promotion proof as **self-host + all tests passed**,
where "all tests passed" means a full run with **`skip_holes == 0`** — because a
skip is scored *passlike*, so a job that never ran is invisible.

The reasoning is right. The threshold is unreachable.

## Measured, not inferred

```
full-tier runs on seven by skip_holes: {1: 120, 2: 1, None: 9}
```

Zero runs at 0, across the entire archive. The hole is a permanently unrunnable
rdrand job: seven is dual E5645 — **Westmere, which predates RDRAND** — and
`grep rdrand /proc/cpuinfo` on plexus returns a hit while that job cannot run on
seven at all. Track T moved to seven on 2026-08-29 and seven is where the
sweeping happens.

So the promotion gate has been unsatisfiable since that move, and nothing
reports it as unsatisfiable — the flag is described in CLAUDE.md as **not built
yet**, which is the only reason this has not already blocked a promotion.

## OVERTAKEN IN PART, 2026-09-16 — the host moved, and the measurement moved with it

**This ticket's blocking claim is no longer true, and the reason is that the
sweeping host changed rather than that anyone acted on it.** Track T ran on seven
when this was filed; plexus retired to **borg** on 2026-09-11. Measured today over
`devdocs/progress/tstate/runs-borg.ndjson`:

```
borg full-tier runs: 672   with skip_holes == 0: 114   with skip_holes > 0: 0
earliest zero: 2026-09-11T19:51:21Z   latest: 2026-09-16T10:01:36Z
```

The 114 begin at the handover, so **every borg full run has met the literal
`skip_holes == 0` gate**, and the newest one also records `skips=0`,
`timed_out=False`, `unreached=0`. The rdrand hole was seven's hardware — dual
E5645, Westmere, no RDRAND — and seven is not the sweeping host any more.

**What this does NOT settle, and the distinction is the whole reason not to close
this.** The fork was never "is the gate currently passable"; it was **what
proof-grade should MEAN when a host has a structural hole**, and that question is
exactly as open as it was. What changed is its urgency: nothing is blocked today,
so a ruling costs nothing and buys the property before the next host move rather
than after it. **Option 1 (literal `skip_holes == 0`) now has a price of zero on
the current host**, which it did not when this was written, and that is new
information about the option rather than a decision.

**This is the shape the owner named on 2026-09-10** — a ticket closed by events,
sitting in a folder, its own body recording that its blocker was gone. It was
found by a watch check-in reading the archive for something else, not by triage.

## Why this is the exact mirror of the rule that generated it

CLAUDE.md's own guard rule says **a guard that cannot fail is not a guard, and
it prints PASS.** This is the inverse and it is just as bad: **a gate that
cannot pass is not a gate — it is a permanent block wearing the costume of
rigor.** Both failures come from a threshold nobody tested against real data;
the guard version was caught by a positive control, and this version needs the
same thing — a *negative* control, a run that MUST qualify.

## The fork

1. **Literal `skip_holes == 0`.** Honest and simple, but it means promotions can
   only ever be proved on a host that can run every job — in practice plexus —
   giving up seven's ~1.7x aggregate for exactly the runs where breadth matters
   most.
2. **An enumerated per-host allowlist of structural holes** (recommended). The
   flag becomes "no skip holes *outside the recorded set for this host*". A NEW
   hole still fails it, which is the property the rule exists for, and the
   allowlist is itself checkable — an entry has to name the job and the hardware
   reason. Cost: the allowlist can rot into a dumping ground if entries are
   added without a reason, so entries need to be justified and reviewed.
3. **Host-qualified proof** — the flag records WHICH host proved it, and a
   promotion needs a host with no holes in the relevant area. More precise,
   more machinery.

## Recommendation

**Option 2**, with two conditions that come straight from this repo's own
history: the allowlist is **enumerated, not a count** (so "1 hole" cannot
silently become a different hole), and the flag ships with **both** controls
asserted — a `quick`-tier run that must classify not-proof-grade (free, per
CLAUDE.md), and a real full run on seven that **must** classify proof-grade,
which is the control this ticket exists because nobody had.

Filed by the Track U session 2026-08-31 from an observation frank-coordinator
surfaced and explicitly did not act on. **Not urgent** — the flag is unbuilt and
no promotion is pending — but it must be settled *before* the flag is built, or
it gets built to the unreachable threshold.
