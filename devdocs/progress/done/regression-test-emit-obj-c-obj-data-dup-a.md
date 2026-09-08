---
prio: 70
track: A
---

> **Track A from the job NAME `test-emit-obj`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/c_obj_data_dup_a.c`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-emit-obj#src:test/c_obj_data_dup_a.c at 1b59d1bbc364 in step 1/52, `./compiler/pascal26 --emit-obj test/c_obj_data_dup_a.c /tmp/cods_dup_a.o` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-08T04:37:15Z
- **Test source:** test/c_obj_data_dup_a.c test/c_obj_data_dup_b.c +15
- **Failing step:** line 1 of 52 of the job's recipe; it names `test/c_obj_data_dup_a.c`.
  ```
  ./compiler/pascal26 --emit-obj test/c_obj_data_dup_a.c /tmp/cods_dup_a.o
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#src:test/c_obj_data_dup_a.c'` at 1b59d1bbc364eed83812303246711467fd2dd7c5

## Range
> **The named sha `1b59d1bbc364` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1b59d1bbc364`, last good `1e5371209512`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26: error: compiled successfully but wrote no output file: /tmp/testmgr-scratch-4008039/cods_dup_a.o
(tail)
pascal26: error: compiled successfully but wrote no output file: /tmp/testmgr-scratch-4008039/cods_dup_a.o
  the code was generated; the artefact is not on disk or is empty.
  usual cause: a missing or unwritable directory in that path.

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-08 — auto-closed by the seven watcher: `test-emit-obj#src:test/c_obj_data_dup_a.c` passes at d0e253df7e7a (tier full); it was red at 1b59d1bbc364. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.

## RESURRECTED BY ACCIDENT, AND MERGED BACK — read this before the triage below

This ticket was closed by the seven watcher at `54964cd97` (04:52:10Z) as a
clean rename `backlog => done`. Four minutes later `dae71ffb2` added the triage
below to `devdocs/progress/backlog/…` — a path that no longer existed. That
tree predated the rename, git re-created the file at the old path, and the
rebase merged silently because the two commits touched different paths. The
result was one slug open and closed at once, indistinguishable from a live
ticket in every instrument except a whole-tree duplicate census, and inflating
exactly the open-bug count the owner wants at zero. Found by frankuser's census
at `2a534ba32`: 512 open slugs, 3770 terminal, **one** intersection — this one.
Stub deleted, content merged here. See `tools/twatch_duplicate_slug_devtest.py`
for the guard that now catches it.

## AND THE CLOSE CORROBORATES THE TRIAGE RATHER THAN REPLACING IT

`"closed: job green again"` and `"closed: proven non-causal"` are different
claims and only the first was on the record. Both are true here and the second
is the one that generalises.

The job passed at `d0e253df7e7a` with **no source change in the range** — ten
commits, zero touching `compiler/`, `lib/` or `tools/`. **A job that recovers
on its own with nothing built differently is precisely what a non-causal range
predicts**, so the green is evidence FOR the finding below, not a reason to
stop reading it. Had it stayed red, the range would still have been unsound;
that it went green tells you which of the two remaining explanations —
harness-side, or nondeterministic — is likelier.


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
