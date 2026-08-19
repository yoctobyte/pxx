---
slug: bug-t-a-red-job-records-no-reason
track: T
type: bug
prio: 45
status: backlog
blocked-by: []
summary: "tstate stores a failed job as the bare string `fail` — `\"tools-devtest#00\": \"fail\"` — with no message, no failing sub-check and no log. So a red job in a cascade cannot be triaged from tstate at all: the only way to learn why it is red is to re-run it, and if the cause was environmental or has since been fixed, the reason is gone for good. Same defect class as the empty devtest FAIL line (4d6e626cb), one level up."
owner: plexus-T
---

# A red job records no reason

## The finding

`devdocs/progress/tstate/<host>.json` carries a `jobs` map of 2786 entries whose
values are bare status strings:

    "tools-devtest#00": "fail"

That is the whole record. No message, no exit code, no captured tail, not even
which sub-check inside the job failed — and `tools-devtest#00` is a job that runs
46 separate guard scripts, so "fail" names one of 46 without saying which.

`runs-<host>.ndjson` is no better: each row carries `new_red` / `still_red` /
`fixed` as **lists of job names**, so a run tells you a job flipped and never why.

## Why it matters, measured

2026-08-19: the open cascade at `bad=21f098e32a95` listed 13 jobs, one of them
`tools-devtest#00`. Triaging it from tstate was impossible — the record is the
string `fail` — so establishing anything at all required re-running the job. At
HEAD in a real checkout all 46 guards are green, which means the reason it was
red is now unrecoverable: it is not in tstate, not in the ndjson, not in the
watcher clone (`.testmgr/` keeps no per-job log), and the run is gone.

That is the same shape as the empty devtest `FAIL` line fixed in `4d6e626cb`,
one level up the stack: a report that records **that** something failed and
discards **why**, leaving a reader to substitute a guess. There it cost one
cross-session relay; here it costs the ability to triage a cascade without
re-running it, which is the expensive direction — a full tier is ~1240s.

## The shape of a fix

Store a bounded reason next to the status rather than replacing it: the failing
sub-check's line plus a capped tail (a few hundred bytes) is enough to tell an
environmental failure from a miscompile without re-running anything. Two
constraints the fix must respect:

- **tstate is committed to git**, so the reason must be capped hard and must not
  carry absolute `/tmp` paths (testmgr already rewrites those for expected
  output — the same rule applies here, or every run dirties the file).
- **`jobs` is read by several tools** that assume a bare string. Widening the
  value to a dict needs the readers updated together, or a sibling map
  (`job_reason`) keyed the same way, which is the cheaper change.

## Not to be confused with

The cascade's `bad` sha being a tstate publish commit that touches only
`devdocs/progress/tstate/**`. That is not a mis-attribution: `bad` is the sha
where the reds were **observed**, `good` the last known good, and `range` the
261 candidates still to bisect. It reads like a verdict and is not one, which is
its own small reportability wart, but it is a separate one.
