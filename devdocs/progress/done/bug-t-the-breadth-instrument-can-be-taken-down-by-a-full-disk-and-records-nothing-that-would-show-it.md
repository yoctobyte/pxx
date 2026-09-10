---
track: T
prio: 55
type: bug
status: done
owner: ""
created: 2026-09-07
found-by: frank-subcoord
tags: [twatch, testmgr, tstate, telemetry, infra, falsifiability]
blocked-by: []
summary: "RESOLVED 2026-09-10. Neither tools/twatch.py nor tools/testmgr.py ever asked the filesystem how much room it had -- no statvfs, no shutil.disk_usage, no df -- so seven's ~290 `infra ... no report (rc=1)` rows of 2026-09-07 could not distinguish a full disk from a code bug, and settling it needed a human on the box. Fixed by tools/fsheadroom.py, recorded on every run row, on the infra record (which has no report to hang a field on, and was the ONLY kind of row that outage produced), and as totals in hosts.json outside HW_KEYS so no host's fingerprint moves -- verified identical (3f2b86ea7416) pre-change, post-change and as stored. BOTH RESOURCES, and the threshold is denominated in RUNS rather than percent: 10% free is ~11 more tier runs on seven's 1,048,576-inode tmpfs and ~69 on plexus's 6,283,264-inode ext4, so a percentage does not travel between the boxes. f_files==0 (btrfs/ZFS) is read as no inode limit, not as exhausted. testmgr now refuses below three runs of headroom with verdict INFRA and no jobs, through an emitter shared with the unbuildable-compiler path, rather than dying with ENOSPC partway and reporting a RED against the sources. The positive control is seven's own df output, and every case that asserts the new reading fires also asserts a bytes-only read of the same numbers does NOT -- without which the suite would pass on a shutil.disk_usage guard. Still open: the real-exhaustion control needs a mount, which is the owner's."
---

# What is missing

```
$ grep -rn "statvfs\|disk_free\|shutil.disk" tools/twatch.py tools/testmgr.py
(nothing)
```

`tstate/meta/hosts.json` per host: `cpu, sockets, cores, threads, mhz_max,
mem_total_kb, kernel, gcc, governor, turbo, fp, from`. No disk, no inodes.
A run row (`runs-<host>.ndjson`) carries `date sha tier verdict wall deadline
timed_out unreached reason note code_fp`. No disk either.

# Why it is worth a ticket rather than a one-line fix

**A fingerprint detailed enough to look complete is worse than an absent one.**
`mem_total_kb` is there, so a reader concludes the host's resources ARE
characterised and that disk was considered and found irrelevant. That is the
same failure as an 80%-accurate name: the part you sample confirms it.

**Both failure modes are step changes, not slopes, so "it would have degraded
gradually" does not rule them out.** Bytes exhaust when one large artefact does
not fit; inodes exhaust at a hard ceiling. Measured on seven 2026-09-07: 17
consecutive runs all produced reports, then 8 of 8 fulls produced none, with
natives recovering twice inside the same window. A switch, not a decline --
which is what a threshold looks like from outside.

**INODES, NOT ONLY BYTES.** The plexus incident of 2026-09-06 was **159,442
files** in one orphaned scratchpad from an A/B loop writing a binary and a
`.map` per iteration. Inode exhaustion produces "cannot write, and space is
free", is indistinguishable from a full disk to every caller, and `df -h` alone
comes back reassuring while proving nothing. Whatever is recorded must carry
both, or it reproduces the gap it closes.

# The fix

Call `os.statvfs(REPO)` once per run and put four numbers on the row:
`disk_free_mb`, `disk_total_mb`, `inodes_free`, `inodes_total`. Add the same to
the `hosts.json` fingerprint so a host's baseline is visible. Cost is one
syscall per run against an instrument that currently cannot answer the question
at all.

Two things to get right, both drawn from how this failure actually presented:

- **Record it on EVERY row, including the `infra` ones** -- the rows that carry
  no verdict are exactly the rows where this number decides the diagnosis, and
  they are the ones most likely to be skipped by a patch that adds a field to
  the report assembly, because an infra row has no report to assemble.
- **Sample it at the START of the run, not the end.** A run that failed because
  it filled the disk may have had its artefacts reaped by the time it dies, so
  an end-of-run reading can come back healthy for a run that was not.

# Positive control

Not "the field is present" -- that passes on a host with a healthy disk, which
is every host most of the time. Fill a scratch filesystem (or exhaust its inodes
with an `open()` loop on a small tmpfs) and assert the row records it and that
the recorded number would have discriminated. A control drawn from a healthy box
cannot fail.

# Provenance

Found while diagnosing seven's `no report (rc=1)` streak of 2026-09-07, where a
disk/inode hypothesis was raised, was the leading explanation for the fulls, and
**could not be tested from the archive by anyone not on the box.** The streak
itself is not this ticket.

# CONFIRMED on seven, 2026-09-07 — and it was inodes

This ticket's hypothesis was right, including the part it hedged on. The cause
of seven's streak was `/tmp` **inode** exhaustion:

```
$ df -h /tmp                          $ df -i /tmp
tmpfs  47G  4.1G  43G   9% /tmp       tmpfs  1048576  1048568  8  100% /tmp
```

Eight free inodes out of 1,048,576, with the filesystem **9% full by bytes**.
`testmgr` could not create its scratch directory, died before running a job, and
the watcher wrote `no report (rc=1)`. The streak was ~290 commits over ten
hours, not 13 — it kept going all night, each run testing the tstate commit the
previous run had pushed.

**Settling it took `df -i`, and `df -h` actively pointed the wrong way.** That
sharpens the fix this ticket asks for: a `shutil.disk_usage` or an `f_bavail`
alone would have reported a healthy box during the outage it was added to catch.
The row needs **`f_favail` as well as `f_bavail`** — free inodes and free bytes —
and `hosts.json` should carry both totals, for the same reason the ticket gives
about `mem_total_kb`: a fingerprint detailed enough to look complete is read as
having considered what it omits.

The producer side is now its own ticket:
`bug-t-devtest-and-twatch-helpers-leak-tmpdirs-until-tmp-runs-out-of-inodes`
(prio 80) — ~40 families of never-cleaned temp dirs, `tstate-at.*` alone holding
163,491 inodes in 241 directories. Telemetry makes this visible; only that one
stops it recurring.

Remediation applied the same day: 30,976 stale entries removed, `/tmp` inodes
1,048,568 → 834, and the tier ran again.

## RESOLVED 2026-09-10 (frankB) — `tools/fsheadroom.py`, and the unit is RUNS

Taken together with the producer ticket, as one group: this half makes the
outage visible and only that one stops it, and each without the other is either
an alarm nobody can act on or a silent refill.

### What landed

`tools/fsheadroom.py` — `probe()` returns the four raw numbers from one
`os.statvfs`, `row()` flattens them into archive fields, `runs_left()` and
`low()` interpret. **Raw on the row, judgement separately**, so a later reader
with a better per-run figure can re-derive the verdict from the archive, which
they cannot do if only a verdict was stored.

Wired into:

| where | what |
| --- | --- |
| `testmgr` run start | `describe()` printed on **every** run; `HEADROOM["at_start"]` sampled before anything can consume any |
| `testmgr` report JSON | four fields plus `fs_at: "start"` |
| `twatch` `runs-<host>.ndjson` | all **three** writers, as `{**fs_row(report), ...}` |
| `twatch` `st["infra"]` | the record with no report to hang a field on |
| `hosts.json` | `scratch`, `scratch_bytes_total_mb`, `scratch_inodes_total` |

### The unit is RUNS, and this is the part that travels

A percentage threshold does not survive the trip between boxes. seven's `/tmp`
is a **1,048,576-inode tmpfs**; plexus's is **6,283,264-inode ext4 on a 94G
disk**. "10% free" is about eleven more tier runs on one and sixty-nine on the
other. `runs_left()` returns `(n, which)` — the count **and the binding
resource** — because on 2026-09-07 bytes said 43G free and inodes said eight,
and a caller that prints only `n` reproduces the ambiguity this closes.

The denominator is itself a correction this ticket's sibling already paid for:
consumption tracks **tier runs, not the clock**. Two readings eight hours apart
gave ~11,170 inodes/hour and a date; a third, three hours later, was
byte-identical, because no tier had run. A per-hour rate fails in the direction
that looks like safety on exactly the quiet days when nobody checks.

### `f_files == 0` means "no inode limit", not "no inodes left"

btrfs, ZFS and some overlays allocate inodes dynamically and report zeros. Read
naively that is 0 free of 0 — 100% exhausted, permanently. Those get
`inodes_total: None`, and every consumer treats None as *not rationed here*.
A field that cries wolf gets learned around, and then it is not there on the
day it is right.

### `f_favail`, not `f_ffree` — and `f_bavail`, not `f_bfree`

The daemon is not root, and the reserved pool is not room it can use.

### testmgr now REFUSES rather than dying with ENOSPC

Below three runs of headroom it emits `verdict: INFRA` with **no jobs** and a
reason naming the number, through `write_infra_report()` — split out of
`report_build_failure()` so two INFRA conditions cannot grow two emitters that
drift. No jobs is the load-bearing part: nothing can be diffed to NEW-RED, no
ledger entry opens, no bisect can accuse an innocent commit.

That emitter's own docstring already listed *"a full disk"* as an example of the
condition, while nothing in either program could detect one. The concept was
present and the detection was absent — which is this group's shape twice over.

Three runs and not one: a run that starts on the last unit of headroom fails
partway through and reports a RED, and the failure gets attributed to the
sources. The ten hours are spent either way; refusing spends them saying why.

### The positive control, which is the whole point

`tools/twatch_fs_headroom_devtest.py`, 12 cases. The control is **not** that the
field is present — that passes on a healthy box, which is every box almost all
of the time, and it is the shape this ticket named. Every case that asserts the
new reading FIRES also asserts a **bytes-only reading of the same numbers does
NOT**:

```python
assert fsheadroom.low(OUTAGE)               # 8 inodes free -> flagged
assert "inode" in why                       # ...and it says which resource
assert bytes_only_would_pass(OUTAGE)        # ...and shutil.disk_usage sees nothing
```

`OUTAGE` is seven's actual `df` output of 2026-09-07. Without the third line the
suite would pass just as happily on a guard built from `shutil.disk_usage` — a
control drawn from the wrong population certifies the broken instrument.

Two of the twelve went RED on their first run, both on real defects of mine:
`_count_inodes` was asserted against a **flat** directory, which `os.walk` yields
in one step, so any implementation passes and the early-exit was untested; and
`TESTTMP="${TESTTMP:-/tmp}"` treats an empty string as unset, so the
dangerous-root refusal could never fire for `TESTTMP=""`. Both are recorded
because they are the same class as the thing being guarded — a check that cannot
fail — found inside the guard written to catch it.

### Not done

`hosts.json`'s totals are **outside `HW_KEYS`** deliberately: `fp_of_hardware()`
filters to that tuple, so the fields ride along without entering the hash.
Verified three ways — the fp is `3f2b86ea7416` computed from the pre-change
code, from the post-change code, and as stored in `tstate/meta/hosts.json`. Had
they gone into the tuple, every box in the fleet would have recorded a spurious
hardware epoch on the first run after this landed.

The real-exhaustion control the ticket asks for (fill a scratch tmpfs, assert
the row records it) still needs a mount, which is the owner's. The numbers-based
control above is drawn from the same population and is what makes the guard
falsifiable today.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
