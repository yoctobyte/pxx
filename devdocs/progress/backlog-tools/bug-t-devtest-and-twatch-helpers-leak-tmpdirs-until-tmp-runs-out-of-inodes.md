---
track: T
prio: 80
type: bug
status: backlog
owner: ""
created: 2026-09-07
found-by: frank-seven
tags: [twatch, testmgr, devtest, infra, tmpfs, inodes]
blocked-by: []
summary: "seven's ten-hour `infra ... no report (rc=1)` spin was /tmp INODE exhaustion: 8 free of 1048576, while bytes were only 9% used -- so `df -h` showed a healthy filesystem and `df -i` showed a dead one. The consumer is ~40 families of temp dirs created by devtests and twatch helpers that never clean up; tstate-at.* alone held 163,491 inodes in 241 dirs accumulated over ~31h. Cleaning stale entries took /tmp from 1,048,568 used to 834 and the tier ran again. One-time cleanup does not fix it: the leak refills."
---

# Measured on seven, 2026-09-07

```
$ df -h /tmp                          $ df -i /tmp
tmpfs  47G  4.1G  43G   9% /tmp       tmpfs  1048576  1048568  8  100% /tmp
```

Nine percent full and eight inodes left. Every `mkdir`/`open(O_CREAT)` in `/tmp`
returned **ENOSPC**; the failure surfaced even in unrelated tooling
(`/bin/bash: /tmp/claude-8e57-cwd: No space left on device`). `testmgr` builds
its scratch under `/tmp`, so it died before running a single job and the watcher
recorded `infra <tree> <tier> — no report (rc=1)` — roughly 290 such commits at
~28/hour for ten hours, each testing the tstate commit the previous one had
just pushed.

# Where the inodes were

| family | inodes | dirs |
| --- | --- | --- |
| `tstate-at.*` | 163,491 | 241 |
| `tmp*` (mkstemp default prefix) | 101,200 | — |
| `stale-edge*` | 44,428 | — |
| `trackt-start*` | 28,233 | — |
| `devtest-pinverify*` + `devtest-pinverify2*` | 48,026 | 291 |
| `orphan-frag*` | 21,424 | — |
| `hostepoch*` | 12,372 | — |
| `twatch-stepgate*` | 11,082 | — |
| `pxx_fuzz*` | 11,045 | — |
| `clone-clean*` | 8,318 | — |

~40 families in all, totalling 1,048,561 — i.e. the whole filesystem. This is
not one runaway producer; it is many helpers each leaving a little behind on
every run, which is why it presents as a cliff rather than a slope.

`tstate-at.*` is the largest single family and the clearest case:
`tools/twatch.py:7613` does `dst = dst or tempfile.mkdtemp(prefix="tstate-at.")`
— when the caller passes no `dst` the directory is created and never removed.
241 of them accumulated between 2026-09-05T18:32Z and 2026-09-07T01:25Z, ~2,100
inodes each, because each holds a checkout of the tstate tree.

# Why this is a separate ticket from the telemetry one

`bug-t-the-breadth-instrument-can-be-taken-down-by-a-full-disk-and-records-nothing-that-would-show-it`
(prio 55) is right that the archive cannot distinguish a full disk from a code
bug, and it explicitly anticipated inodes. It asks for a `statvfs` on the row.
That makes the outage **visible**; it does not stop it. This ticket is the
producer side: even with perfect telemetry, `/tmp` refills and the tier dies
again.

**A bytes-only check would not have caught this.** `shutil.disk_usage` reports
bytes; at the moment of failure that read 9% used. Whatever lands for telemetry
must record `f_favail` as well as `f_bavail`, or it will report a healthy box
during the exact outage it was added for.

# Suggested fix

1. Make the leaking helpers clean up — `tempfile.TemporaryDirectory`, or an
   explicit `shutil.rmtree` in a `finally`. `tstate_at()` is the first one to do
   because it is 16% of the filesystem by itself.
2. A sweep at daemon start for the known prefixes older than some age, on the
   same principle as the existing stop-guard cleanup. Cheap and bounded.
3. Record free inodes on the run row (that is the telemetry ticket) so the next
   occurrence is one field rather than a human with `df -i`.

# Immediate remediation applied

Removed 30,976 stale top-level entries from `/tmp` (everything but dotfiles,
`claude-*`, `RustDesk`, `c2.sh`, and anything touched in the previous 60
minutes), with the watcher stopped and no pxx process running.
`/tmp` inodes went **1,048,568 used → 834 used**, bytes 4.1G → 61M. This is a
patch, not a fix: the families above will refill it.

# Refill rate measured 2026-09-08 04:50Z — the ceiling is ~2 days out

The remediation above left `/tmp` at **834 inodes used**. One day later, with no
change to the producers:

```
$ df -i /tmp   -> 1048576 total, 349311 used (34%)
$ df -h /tmp   ->      47G total,     2.3G used (5%)
```

Same signature as the outage: **bytes reassuring, inodes climbing.** At ~350k
per day the ceiling is reached in about **two days**, so this recurs on its own
schedule unless the producers are fixed. The date is the useful part — a reader
who finds this after the next outage should not have to re-derive that it was
predicted.

**The dominant family is NOT `tstate-at.*` — it is `testmgr-*`, and it is an
order of magnitude worse PER INSTANCE.** Measured on seven the same minute:

| family | dirs | inodes | per dir |
| --- | --- | --- | --- |
| `/tmp/testmgr-*` | 42 | 192,118 | ~4,574 |
| `/tmp/tstate-at.*` | 42 | (counted in the outage: 163,491 over 241 dirs) | ~678 |

The individual `testmgr-*` dirs cluster tightly at **~9,070 files each** for the
larger ones — one per tier run, never removed. The equal count of 42 in both
families is what a per-run leak looks like: the two are created by the same
runs, so they accumulate in lockstep and either one alone reads as "some dirs
piled up" rather than as a rate.

**Why the biggest producer was missed the first time:** the outage census ranked
families by TOTAL inodes at the moment /tmp was already full, and at that point
`tstate-at.*` had had ~31h to accumulate while the `testmgr-*` dirs from the
same period had been partly reaped. Ranking by total-at-the-end answers "what is
in there now"; the question is "what puts it there", and those differ whenever
the families have different lifetimes. Rank by **inodes per run**, not by the
standing total.
