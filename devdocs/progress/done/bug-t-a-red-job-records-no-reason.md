---
slug: bug-t-a-red-job-records-no-reason
track: T
type: bug
prio: 45
status: done
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

## Fix

Two halves, both needed — one records the reason, the other decides what may be
kept, and the second is where the correctness is.

### testmgr: `job_reason(job)` — what to record

The log **tail**, not a pattern match. A signature list goes stale silently and
then reports nothing for the failure shapes it has not met yet, which is this
same defect with more code. What the job printed last is true for every shape,
including the ones nobody has seen. Emitted as `"reason"` in the report JSON,
for non-passing jobs only.

Three constraints, all load-bearing and all guarded:

- **Capped** at `REASON_MAX = 400` chars over at most 6 substantive lines.
  tstate is committed to git.
- **`/tmp` scrubbed** to `$TMP`. The run's scratch dir is pid-keyed, so an
  unscrubbed path changes every run and dirties tstate with nothing else moved.
- **Trailing make-noise dropped.** `make: *** [Makefile:N: t] Error 1` is the
  last line of nearly every failing log and says nothing the status and name do
  not. Keeping it would give every job the same reason — the current defect
  wearing a longer string. Dropped from the END only: the same text mid-log is
  a sub-make that failed and recovered, and dropping it there rewrites the story.

An empty return means the log is gone or unreadable and reads that way. It is
never a claim that the job failed for no reason.

### twatch: `update_job_reasons()` — what to keep

A **sibling map** `st["job_reason"]`, not a widening of `st["jobs"]`, whose
values several tools read as bare strings. The ticket called this the cheaper
change; it is also the only one that cannot break a reader not updated in the
same commit.

- A job that is no longer red loses its reason. A stale `why` on a green job is
  worse than none.
- A job the orphan prune dropped from `st["jobs"]` loses it, so this map can
  never outlive the map it annotates.
- **A job THIS RUN produced sets or CLEARS its reason.** If the run had it red
  but recovered no log, the stored reason is deleted rather than left in place.
  Keeping it would attach a previous run's explanation to this run's failure —
  a true sentence about the wrong subject, which is the shape this ticket is one
  instance of.
- Bounded at `JOB_REASON_CAP = 60`, trimmed by sorted name so which survive is
  reproducible rather than dict-order luck, and the trim **prints what it
  dropped**: a silent cap turns "we kept 60 of 300" into "there were 60".

Carried (resumed) jobs keep their reason and are entitled to: `apply_resume()`
passes the earlier report's dicts through verbatim and `load_resume()` refuses a
partial whose compiler sha256 does not match, so a carried result is
attributable to the binary this run tested. A carried dict from a *pre-feature*
testmgr has no `reason` key and therefore clears — unattributable beats
plausible, and it self-heals on the next real run.

### The markdown half

`write_report_md()` dumped one log, for the *first* failure. A 13-job cascade
left the other twelve as bare names in NEW-RED / STILL-RED — the document a
human reads days later said WHICH job and not WHY. Every red in those lists now
carries its reason (trimmed to 160 chars; it is a scannable list, not the
durable record).

## Log
- 2026-08-19 — fixed. `tools/job_reason_devtest.py`, 20 checks; 4 go red against
  a neutered version (no noise strip, no scrub, no stale-clear).
  `PXX_TRACK=T make tools-devtest` → 48 guards green.
- 2026-08-19 — resolved, commit 68a65fff0.
