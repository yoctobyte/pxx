---
summary: "tstate records a SKIPPED job as \"pass\", so a green published state cannot be distinguished from one that actually ran — cross-host coverage differences are invisible exactly when they matter"
type: bug
track: T
prio: 50
---

# `skip` is published as `pass`, so green does not mean "ran"

- **Type:** bug (Track T — `tools/twatch.py`, tstate schema)
- **Opened:** 2026-08-03 by `claude@xeon`, split out of
  [[bug-t-corpus-regex-invents-phantom-tree]] item 3. That ticket fixed the two
  self-contained halves (the phantom corpus name, and one absent corpus taking
  an unrelated regression test down with it) and deliberately left this one,
  because it changes the tstate schema and wants a migration rather than a
  drive-by.

## The defect

`tools/twatch.py:587`:

```py
now = {job_key(j): ("pass" if j["status"] == "skip" else j["status"]) ...}
```

A job skipped because its corpus tree is absent on this box is published as
`pass`. The run-time warning is loud — `!! CORPUS MISSING — 33 job(s) will
SKIP` — but the **published** state is silently green, and every consumer of
`tstate/*.json` (cross-host comparison, `--status`, the dashboard, the cutover
decision) reads it as covered.

The comment's reasoning is sound as far as it goes: mapping skip to pass closes
an open regression when a box legitimately cannot run a job. The defect is that
it does so by **destroying the distinction**, rather than by treating a
third state as non-gating.

## Why it matters

Green must mean "ran and passed". Concretely:

- On xeon, 33 of the full tier's jobs skip when the corpus trees are unfetched
  — including all 24 c-testsuite conformance jobs. The verdict is still GREEN.
- A per-host `skip` count is the only thing that makes host-to-host coverage
  differences visible **at cutover time**, which is precisely when the fleet
  decides to trust one box's green over another's.
- It was also how the phantom-corpus bug stayed invisible for so long: the
  affected job read `pass` on every host while having never executed anywhere.

## Shape of the fix

1. Publish `skip` as its own status in `tstate/<host>.json`.
2. Keep it non-gating: `new_red` / `still_red` must not fire on it, and a job
   that goes red → skip still closes the open regression (today's behaviour).
3. Migration: existing `borg.json` / `xeon.json` carry `pass` for jobs that
   were skips. Readers must tolerate a missing/unknown status, so the safe
   order is (a) teach every reader the third state, (b) start writing it.
4. Report the per-host skip count in the tstate summary and the dashboard, so
   the coverage gap is visible without diffing two json files.

## Gate

`tools/testmgr.py --tier quick` green, plus a devtest over `diff_jobs` covering:
skip is not new-red; red → skip closes the regression; skip → red opens one.
