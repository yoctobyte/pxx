---
slug: regression-test-sqlite-threads-aarch64-output-mismatch-untracked-since-08-29
track: A
prio: 55
type: regression
status: unfinished
owner: frankS
blocked-by: []
summary: "NOT REPRODUCIBLE ON PLEXUS: PASSES 4/4 at HEAD with the amalgamation copied in, 37s of a 120s budget (62s under a 12-way CPU load). The report cannot say why it fails on seven, because `FAIL (output mismatch)` was ALSO what a TIMEOUT printed -- measured: `timeout 5` gives rc=124, empty output, and that branch. The runner now separates the two and prints the actual output; the next full sweep on seven answers this. Track T question inside: the sibling qemu runners stretch their inner budget by TESTMGR_LOAD_SCALE and this one does not."
---

# `test-sqlite-threads-aarch64` red since 2026-08-29, and untracked

- **Filed:** 2026-08-31 by frankA, from the full-tier RED on `712c57daf`
  (report `20260831T015613Z-712c57d-seven.md`). I chased it because I had just
  changed the aarch64 dispatch stub and "STILL-RED" is not by itself proof the
  job is not yours.

## Not mine — and that is the cheap half

Already red at **2026-08-30T02:54:19Z**, compiler `67f47b5bc540`. My aarch64
change (`09c62ef2e`) landed **2026-08-31 03:41**, twenty-five hours later. Same
job, same `#src:compiler/.pascal26.fixedpoint` key, same failure text.

**The expensive half is that nobody owns it**, which is why this exists.

## What it does

```
test-sqlite-threads: building threadsafe sqlite (aarch64) ...
ok: .../csqlite_thread_test26_aarch64  [code=6946584B data=84424B bss=118128B procs=4393]
test-sqlite-threads: FAIL aarch64 (output mismatch)
```

It **builds** and then produces the wrong output. Expected is
`shared OK / perthread OK / all OK` (`tools/run_sqlite_thread_test.sh`). The
report does not carry the actual output, so which of the three lines diverges is
unknown and is the first thing to get.

## Duration, and the tracking gap

RED in every full-tier report on 2026-08-29, 08-30 and 08-31 — fourteen
consecutive sweeps on 08-30/31 alone. Searched `urgent/ working/ unfinished/
backlog/ backlog_new/ blocked/`: **no open ticket.** There are two CLOSED ones
for this exact job (`regression-test-sqlite-threads-aarch64-00`,
`regression-test-sqlite-threads-aarch64-run-sqlite-thread-test`, the latter fixed
2026-07-14 as `7dc1ab65`), both **auto-filed by twatch** — so the normal
mechanism exists and did not fire this time. Worth a glance from Track T:
a job that goes red while the watcher is mid-restart, or that never presents a
NEW-RED transition, appears to get no ticket and then reads as furniture in every
later report.

## NOT REPRODUCED — read this before starting

`tools/run_sqlite_thread_test.sh aarch64` **SKIPs** in this checkout:
`no sqlite amalgamation at library_candidates/sqlite/sqlite3.c`. The Track T box
has it (it builds a 6.9 MB binary). So everything above is from the reports, and
nothing here is a local observation of the failure itself.

## Suggested first steps

1. Get `library_candidates/sqlite`, run the script, and capture the **actual**
   output — the report only says "mismatch".
2. Check the three sibling arches. `x86_64`/`i386`/`arm32` are not in the
   still-red list, so this looks aarch64-specific, which narrows it a lot.
3. Only then bisect. The window is wide (red by 08-29) and the two previous
   instances of this job were different causes, so do not assume it is the same
   bug returning.

## 2026-08-31 — REPRODUCTION ATTEMPTED ON PLEXUS. It passes here, and the report could not have told anyone why

Claimed by frankS. The amalgamation exists on this box at
`/home/neo/pxx/library_candidates/sqlite/` (also `/home/neo/trackt-watch/`), so
the "no local repro" blocker in the section above is gone — copy it into
`library_candidates/` (gitignored) and the script runs.

### It passes here

Four runs at HEAD (`d63c01aab`, compiler `209010b3252f`):
`PASS aarch64 (libc-free, shared+per-thread)`, every time. The binary matches a size tuple seven
has produced: `code=6946584B data=84424B bss=118128B procs=4393`.
**That comparison is NOT controlled** (frankT, checking the archive): the tuple
drifts with the tree and seven has written four distinct ones —
`bss=113840/procs=4343`, `118120/4392`, `118120/4393`, `118128/4393` — so
"identical" only means anything **sha-matched**, and this was not. The
conclusion survives it, because the build succeeds on both and only the run
diverges; the word "identical" must not travel onward.

### The report was structurally unable to distinguish two very different failures

`tools/run_sqlite_thread_test.sh` compared the captured output against the
expected three lines and printed `FAIL (output mismatch)` on any difference —
**including the case where `timeout` had killed the run and the output was
empty.** Measured on the same binary:

```
timeout 5 tools/run_target.sh aarch64 <bin>   ->  rc=124, got=[]   -> "output mismatch"
```

So three days of identical red lines are consistent with *either* a miscompile
*or* a job that is merely too slow on that box, and nothing in the report
separates them. Fixed: the runner keeps `timeout`'s exit code, names a timeout
as a timeout, prints the elapsed time against the budget, and **prints what it
actually got**. The report quotes that text and nothing else, which is why the
output had to move into it rather than stay in a shell variable.

`CSTT_RUN_TIMEOUT` was added so the new branch can be *exercised*:
`CSTT_RUN_TIMEOUT=5 tools/run_sqlite_thread_test.sh aarch64` prints
`FAIL aarch64 (TIMED OUT after 5s; TESTMGR_TIME_SCALE=1)`. Asserted, because a
diagnostic branch nobody has watched fire is a guess written in the imperative.

### Timing, so the next report can be read against a number

| condition | aarch64 run | budget |
| --- | --- | --- |
| plexus, load ~4 | **37s** | 120s |
| plexus, 12 CPU burners (load 14) | **62s** | 120s |
| x86_64, same box | 1s | 60s |

A 2x margin under saturation. That does not rule the timeout hypothesis out —
seven is a different box and runs a 16-way matrix — but it does not support it
strongly either, and it is the reason this ticket is parked rather than closed
with a guess.

### For Track T, and this is the part I did not act on

Two things about the harness, neither of which is mine to change:

**RULED, 2026-08-31, by frankT, who owns both:** leave item 1 exactly as it is —
sizing it before seven's first honest report is the guess this ticket was parked
to avoid, and *"if it turns out to be needed, move the OUTER first, then the
inner"*. Item 2 is confirmed and filed as its own ticket (`c20f500fb`). Seven
sweeps full tier about every 13 minutes, so the answer arrives on its own.

1. **The inner budget does not stretch under load.** `run_c_conformance.sh` and
   `run_fgl_corpus.sh` both multiply their inner `timeout` by
   `TESTMGR_LOAD_SCALE` as well as `TESTMGR_TIME_SCALE`, with a comment saying
   exactly why: *"TESTMGR_TIME_SCALE is an idle hardware probe and stays ~1 on a
   fast box, so it never captures this; cap/cores does"* — written for
   `regression-testmgr-conformance-shard-timeout-under-load`, which is the same
   failure shape (qemu-user, inner timeout, exit 124 read as a red).
   `run_sqlite_thread_test.sh` uses only `TESTMGR_TIME_SCALE`. I did **not**
   add the multiplication, because the `qemu` class's OUTER job timeout is 240s
   and the inner aarch64 budget is already 120s: doubling the inner one can push
   past the outer, converting a diagnosable inner failure into a less
   informative outer kill. That is a budget decision that needs seven's numbers.
2. **The auto-ticket never fired — CONFIRMED, and the number is worse than
   "fourteen sweeps".** frankA's read was right and frankT checked it twice:
   filing is gated on `new_red`, which is a TRANSITION against the stored job
   state, so a job that is red in the baseline can only ever be ticketed by
   going green and red again. And **81 of 81 full-tier reports on seven carry
   this job red** — every full report that host has ever written, from
   2026-08-29T16:51:31Z to 2026-08-31T02:09:38Z. It has never once been green
   there, so it never presented a transition, so it could never have been
   ticketed. A guard that cannot fire and prints nothing at all.
   The fix is NOT to loosen the suppression (all three gates correctly refuse to
   LOCALIZE a red they cannot attribute) — it is that localizing and noticing are
   different jobs and only the first needs a transition. Filed by frankT.

### What decides this

The next full-tier sweep on seven. It will now print either
`TIMED OUT after Ns` — a Track T budget question, with the numbers above to
size it — or `output mismatch, exit N` **with the actual three lines**, which
localises a wrong answer to `shared`, `perthread` or `all` and makes it a Track
A bug with a place to start. Parked in `unfinished/` until then rather than
closed, because nothing here has established a cause.
