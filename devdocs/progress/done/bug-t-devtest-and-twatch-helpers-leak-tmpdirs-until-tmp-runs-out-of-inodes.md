---
track: T
prio: 80
type: bug
status: done
owner: ""
created: 2026-09-07
found-by: frank-seven
tags: [twatch, testmgr, devtest, infra, tmpfs, inodes]
blocked-by: []
summary: "RESOLVED 2026-09-10. Seven's ten-hour `infra ... no report (rc=1)` spin was /tmp INODE exhaustion: 8 free of 1048576 while bytes were 9% used, so `df -h` showed a healthy filesystem and `df -i` a dead one. It was NOT ~40 leaking families needing ~40 fixes, which is what two correct censuses of this ticket concluded and why neither could converge: `TMPDIR` is read by ~20 tools/*.sh as ${TMPDIR:-/tmp}, honoured natively by all ~150 tempfile.mkdtemp() sites, and PRESERVED BY NAME in testmgr's own ENV_ALLOW -- and was set by nothing in the repository. A channel wired end to end with no producer, so every site fell through to /tmp correctly and forever. Fixed by pinning TMPDIR to RUN_TMP/tmp in BASE_ENV_KEEP (the identical repair TESTTMP got a month earlier, three lines above it) so every job's scratch inherits the two teardowns RUN_TMP already had. Also: twatch.py had no shutil.rmtree at all; and testmgr-* was never leaking -- LOGDIR_KEEP_MAX bounds DIRECTORIES, and 40 of them is 2,747 inodes on plexus and ~190,000 on seven, so it was sitting at a ceiling priced in the wrong unit. tools/reap_tmp.sh backstops what the pin cannot reach. NOT fixed and named: ~60 prefix-less mkdtemp sites landing on `tmp*`."
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

## Second reading 2026-09-08 13:14Z — the extrapolation holds, and now it is a rate

```
$ df -i /tmp   -> 1048576 total, 443118 used (43%),  605458 free
```

Two points now instead of one: 349,311 at 04:50Z, 443,118 at 13:14Z — **+93,807
in 8h24m, ~11,170/hour, ~268k/day.** The one-point extrapolation above guessed
~350k/day from a single 24h delta; the measured rate is lower but the same order,
and the conclusion is unchanged: **605,458 free inodes / 11,170 per hour = ~54
hours, so the ceiling falls around 2026-09-10 late** unless a producer is fixed.

Recorded because a prediction nobody re-measures is indistinguishable from one
that was wrong. Bytes at this reading: 5% — still reassuring, still irrelevant.

## CORRECTION 2026-09-08 16:15Z — the driver is TIER RUNS, not wall-clock hours

The section above quoted **~11,170 inodes/hour** and put the ceiling "around
2026-09-10 late". **The per-hour framing is wrong** and a third reading falsifies
it directly:

```
13:14Z  ->  443118 used
16:15Z  ->  443118 used     (identical, three hours later)
```

Zero drift across 3h01m, because **no tier ran in that window** — seven's last
run row is 11:52Z (opt), the watcher is `active` with 20h uptime and NRestarts=0,
and a `ps`-based scan finds no `testmgr` process. `/tmp/testmgr-*` went 42 -> 41
over the same period: the 6h reaper removed one and nothing created any.

So the two earlier readings did not measure a rate against the clock; they
measured **however many tier runs happened to fall between them**. Consumption
is per-run — ~9,070 inodes per `testmgr-*` dir, ~678 per `tstate-at.*` — so the
correct denominator is the watcher's sampling cadence, which varies with how
fast the tree moves and goes to zero on a quiet tree.

**What this does and does not change.** The ceiling is still real and still
approached monotonically, because nothing frees these; what moves is the DATE,
which is now a function of fleet activity rather than of the calendar. A busy day
reaches it sooner than 09-10 and a quiet weekend never does. **Do not quote a
date from this ticket** — quote free inodes (605,458 at this reading) divided by
the ~10k-per-run figure: roughly **60 more tier runs**, whenever those occur.

Recorded because the per-hour number was relayed to the owner before this
reading existed, and a prediction with the wrong denominator fails in the
direction that looks like safety on exactly the quiet days when nobody checks.

## RESOLVED 2026-09-10 (frankB) — it was never ~40 leaks; it was ONE absent producer

**The census ranked FAMILIES, and families are the wrong axis.** Both readings
above are correct and neither could show this, because ranking by family — by
total, then corrected to per-run — answers "which directory names are piling
up". Every answer to that question is a name, so every answer implies a fix per
name, and ~40 fixes that must each be remembered is not a fix at all. The
question that dissolves it is **what do these sites have in common**, and the
answer is one line long:

```
$ grep -rn 'TMPDIR' tools/ Makefile          # ~20 readers, every one correct
$ grep -rn 'TMPDIR *=\|export TMPDIR' .      # (nothing)
```

`TMPDIR` is read by ~20 `tools/*.sh` as `${TMPDIR:-/tmp}`, honoured natively by
every one of the ~150 `tempfile.mkdtemp()` calls in `tools/*_devtest.py`, and
**preserved by name in testmgr's own `ENV_ALLOW`** — and nothing in the entire
repository has ever set it. A channel wired end to end with no producer, so
every site fell through to `/tmp` and left its directory there.

**Nothing was wrong at any of those ~40 sites.** They are all correct. That is
why the census could not converge: it was enumerating symptoms of an absence,
and an absence has as many symptoms as there are sites that would have used it.

### The fix, and why it is one line where the census implied forty

`"TMPDIR": JOB_TMP` in `testmgr.py`'s `BASE_ENV_KEEP`, with `JOB_TMP =
RUN_TMP/tmp`. Every job a tier runs now writes its temp dirs inside `RUN_TMP`,
which already had **two** teardowns nobody had to write: `drop_run_tmp()` at
exit, and `sweep_orphan_tmp()`'s pid-keyed reclaim, which is the one that
survives the SIGKILL testmgr routinely sends its own jobs.

The repair has a precedent three lines above it in the same dict, and the
precedent states this ticket's shape in its own words. `TESTTMP` had exactly
this bug in 2026-08: *"Reading TESTTMP taught the MATCHERS the value; it did not
teach the PRODUCER."* One variable over, one month later, same dict.

`TMPDIR` was also **removed from `ENV_ALLOW`** in the same change. A name in
both sets resolves differently depending on which branch of `job_env()` runs —
the allowlist loop assigns *after* the `BASE_ENV_KEEP` copy, so the parent would
have won there while the pin won under `TESTMGR_INHERIT_ENV=1`. No variable was
in both before; keeping it that way is what stops that asymmetry from mattering.

### Three more, all found by following the same question

- **`tools/twatch.py` contains no `shutil.rmtree` at all.** 9,577 lines of
  daemon, creating three families of temp dir, removing none. `materialize_tstate`
  and the pin scratch now register an `atexit` reap of the directory *they*
  created; a `dst` passed in stays the caller's. atexit is right here and would
  be wrong in the daemon: both callers (`twatch_web.py`, `twatch_live_code.py`)
  render once and exit, and the daemon itself never calls it.
- **`testmgr-*` WAS NEVER LEAKING.** `LOGDIR_KEEP_MAX = 40`, and the census
  counted 42. It was sitting at its ceiling, and **the ceiling is priced in
  directories by a comment that costed it in bytes** (*"128 dirs / 392 MB
  observed"*). Measured 2026-09-10: 40 log dirs is **2,747 inodes on plexus**
  (quick tiers, 67 files each) and **~190,000 on seven** (fulls, ~9,070 each) —
  18% of that box's tmpfs, held permanently, entirely within budget. A bound
  cannot see a resource it is not denominated in; `LOGDIR_KEEP_INODES` now sits
  beside the count.
- **`tools/reap_tmp.sh`**, committed with a `trap ... EXIT` as CLAUDE.md
  prescribes, for the population the pin cannot reach: what is already standing,
  a devtest run by hand, and a helper killed by SIGKILL. It derives its prefix
  list from `tools/` source rather than hardcoding 96 of them, so it cannot
  quietly stop covering the newest families — a hardcoded list would print a
  confident `reaped 0` during the next outage.

### Measured after, on plexus

`tools/reap_tmp.sh -n` finds **252 directories, 142,933 inodes** standing here —
the same leak, on a box nobody had looked at, at 3% inodes because ext4 gives it
6,283,264 rather than a tmpfs's 1,048,576. **Not reaped:** plexus is under no
pressure and other sessions hold checkouts on this box, so clearing 143k inodes
buys nothing and could disturb a peer's in-flight scratch.

### NOT fixed, and named rather than papered over

~60 `mkdtemp()` calls pass **no prefix** and land on tempfile's default `tmp*` —
101,200 inodes in the outage census. Under a tier the pin now covers them; run
by hand they still leak, and `reap_tmp.sh` deliberately does not glob `tmp*`,
which is far too broad to delete by pattern in a shared `/tmp`. The fix for
those is a prefix at each call site, which is a real ~60-site edit and is not
this ticket.

Guarded by `tools/twatch_fs_headroom_devtest.py` (12 cases), which asserts the
pin is a SET rather than a pass-through by driving a real subprocess through
`job_env()` and asking where its `mkdtemp` landed — asserting the field is
present would have passed on the pass-through that was already there.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
