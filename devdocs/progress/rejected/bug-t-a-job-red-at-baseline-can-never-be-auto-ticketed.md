---
track: T
prio: 55
type: bug
status: rejected
found: 2026-08-31
found-by: frankA / frankS / frankT
---

# A job that is red at BASELINE can never be auto-ticketed, and then reads as furniture

`twatch` files regression tickets off `new_red`, which `diff_jobs` computes as a
**transition** against the stored `st["jobs"]`. So a job that is already red when
the baseline is written can only ever produce a ticket by going **green first and
then red again**. If it never goes green, it is never new, and no ticket is ever
filed — while it appears in every later report as a `STILL-RED` line that reads
like known, owned furniture.

## The measurement that makes it concrete

`test-sqlite-threads-aarch64#src:compiler/.pascal26.fixedpoint` on host seven:

**81 of 81 full-tier reports carry it red** — every full report seven has ever
written, `2026-08-29T16:51:31Z` through `2026-08-31T02:09:38Z`. It has never once
been green on that host, so it has never presented a transition. Two *closed*
tickets exist for this same job from earlier hosts, both filed by twatch when it
did transition there; this instance had to be filed by hand after three days
(frankS, who also fixed its diagnostic in `fc5762a2f`).

**A guard that cannot fire, printing nothing** — the same shape as the saturation
check that scored 0.000 and reported PASS, one step further along: this one has
no output at all to be suspicious of.

## Do NOT fix it by loosening the suppression

`ticket_suppression()` is load-bearing and its docstring is right: a false ticket
lands on the board at prio 70, names an innocent sha, and costs another agent a
triage cycle. All three gates are deliberate —

- `not had_baseline` — with no baseline every red is "new", so NEW-RED carries no
  information;
- `new_red and not rng` — 0 testable commits since the last tested sha, so an
  entry would name a sha that cannot have caused it;
- `n_new_red > INFRA_FAULT_FRAC * n_jobs` — an environment fault, not a change.

Each correctly refuses to *localize*. None of them is wrong. The gap is that
**nothing ever asks the other question**: which jobs are standing red with no
open ticket?

## The shape of the fix: a reconciler, not a looser gate

A periodic pass over `st["jobs"]` plus the runs archive: any job red for ≥ N
consecutive runs on a host with no open ticket gets one — filed as *"standing red,
not localizable"*, explicitly NOT naming a suspect sha, which is what keeps it
from being the false ticket the suppression exists to prevent. Localization and
noticing are different jobs and only the first needs a transition.

Data needed is already on disk; this is a read, not a new measurement.

## The positive control ships with it, and it is free

**The reconciler MUST report `test-sqlite-threads-aarch64` on its first run**, and
that must be asserted, not observed. A reconciler that does not surface an
81-of-81 standing red is not working — and per
`devdocs/dev/debugging-playbook.md`, a guard that cannot fail is not a guard.
Second control, also free: a job red for 1 run must NOT be reported.

## Open sub-question, not blocking

Whether the threshold is per-host or global. Seven is the only host sweeping full
tier right now, so per-host is sufficient today and is the cheaper thing to build.

## Rejected 2026-09-02 — the Track T tooling backlog was cut as a pile

Owner decision, not a judgement on this ticket individually. 73 of the 74 open
`track: T` tickets were filed between 2026-08-31 and 2026-09-02, 58 on one day.
The pile was too large to work through, and a ticket nobody will fix does not sit
neutrally: it stays in the ranker forever at zero value, which is the same
argument CLAUDE.md already makes for `rejected/` over a low prio.

Four were kept, on a purely structural test — an active umbrella, or a hard
`blocked-by:` edge from live non-T work: `umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**This is a reversible archive, not a deletion.** If one of these is refiled
later, it should be refiled with the evidence that makes it worth doing rather
than restored wholesale.
