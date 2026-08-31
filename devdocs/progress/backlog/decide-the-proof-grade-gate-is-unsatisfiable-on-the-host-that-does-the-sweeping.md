---
track: U
prio: 55
type: decide
blocked-by: []
summary: "CLAUDE.md's -O3 promotion gate defines proof as a full run with `skip_holes == 0`. Measured 2026-08-31 over seven's whole archive: 121 full-tier runs, 120 with skip_holes=1 and one with 2 — NONE at 0, ever. The hole is a permanently unrunnable rdrand job, and it is structural: seven is dual E5645 (Westmere, no RDRAND) while plexus has it. Since Track T moved to seven on 2026-08-29, the gate as written can never be met, so NO -O3 pass can ever be promoted. Needs a ruling on what proof-grade means in the presence of a permanent host hole; recommendation is an enumerated per-host allowlist so a NEW hole still fails."
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
