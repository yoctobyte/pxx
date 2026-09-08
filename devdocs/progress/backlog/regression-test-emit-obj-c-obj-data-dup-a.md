
---

## Triage: this is not a source regression, and the range is not evidence

Added by frank-coordinator 2026-09-08, read-only measurement. The RED stands —
only the attribution is impossible.

**Every commit in the range is irrelevant to this job.** Over
`1e5371209512..1b59d1bbc364`:

- **10 commits. ZERO touch `compiler/`, `lib/` or `tools/`.**
- Exactly **2** touch anything outside `devdocs/` and `docs/` — which is why
  the header says "2 commit(s) in range": that is the `needs_test` population,
  `NOTEST_PREFIXES = ("devdocs/", "docs/")`.
- **Both of those two touch only `test/pascal-conformance/pxx.skip`**
  (`796fa1c3b`, `624c60da9`) — a Pascal conformance skip list. A C
  object-emission job does not read it.

The header already says the *named* sha touches no buildable file. The
range-wide statement is the one that ends the search: a reader told the accused
is innocent still assumes one of the others is guilty.

**Two of the ten commits are the coordinator's own prose-docs pushes.** A seat
that could not have caused a compiler defect was inside its blame population,
and an idle bisect over this range would have converged on a `pxx.skip` edit
and named it for an `--emit-obj` failure, with the confidence of a real bisect.

## Disk: MEASURED and EXCLUDED, not merely unconsidered

Recorded because an untested hypothesis and an excluded one look identical to
the next reader, and this one will be reached for again — the compiler's own
message (*"usual cause: a missing or unwritable directory"*) points straight at
it, and ENOSPC presents identically to a write that silently produced nothing.

frankuser, read-only on seven at **04:50Z**, thirteen minutes after the RED:

    df -i /tmp -> 349,311 of 1,048,576 inodes used (34%)
    df -h /tmp ->        2.3G of 47G used          (5%)

Neither resource was near a ceiling. The climb is monotonic between reaper
firings and `systemd-tmpfiles-clean.timer` last fired 17:48Z the previous day,
next at 17:48Z — so nothing freed inodes between 04:37Z and the reading, and
whatever the count was at the failure it was **at most 349k**. **ENOSPC is out
in both dimensions, and the reaper did not race the run.**

**This exclusion has a date on it and does not generalise.** Inode use was 834
after the previous cleanup and 349,311 a day later — roughly 350k/day against a
1,048,576 ceiling, so the volume reaches it in about two days and the outage
recurs on its own schedule. `/tmp/testmgr-*` is the dominant producer at
**192,118 inodes across 42 directories** (~9,070 per tier run), not `tstate-at.*`
at ~678 per directory — which the earlier outage census named because it ranked
by standing total rather than by inodes per run. Appended to the prio-80
producer ticket at `b617c3acb`. **If ENOSPC is out today it will not be out on
Thursday**, and a range guard that excluded the disk once must not be read as
having excluded it always.

## What is left

No source change, no disk, no reaper. That leaves **harness-side or
nondeterministic**. Do not bisect this range; look at the box, the harness, and
whether the job reproduces at HEAD.

Guarded in the tool as of this commit: `range_non_causal()` in `tools/twatch.py`
classifies exactly this shape, the stub banner says it, and `bisect_step`
declines. Positive control in `tools/twatch_range_causality_devtest.py` — a
range containing a `compiler/` commit must still bisect.
