---
track: T
prio: 55
type: bug
status: backlog
owner: ""
created: 2026-09-07
found-by: frank-subcoord
tags: [twatch, testmgr, tstate, telemetry, infra, falsifiability]
blocked-by: []
summary: "Neither tools/twatch.py nor tools/testmgr.py ever asks the filesystem how much room it has -- no statvfs, no shutil.disk_usage, no df -- and no tstate row carries free bytes or free inodes. So when a watcher host cannot write, the archive records `infra ... no report (rc=1)` and nothing that distinguishes a full disk from a code bug. Measured 2026-09-07 against seven's 13-run infra streak: the disk hypothesis could be neither confirmed nor refuted from the archive at all, and settling it needs a human on the box running `df`. One statvfs per run, recorded on the row, would have made it a single field. The misleading part is that tstate/meta/hosts.json is otherwise DETAILED -- cpu, sockets, cores, threads, mhz_max, mem_total_kb, kernel, gcc, governor, turbo -- so its silence on disk reads as `disk is not a variable here` rather than `nobody added it`."
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
