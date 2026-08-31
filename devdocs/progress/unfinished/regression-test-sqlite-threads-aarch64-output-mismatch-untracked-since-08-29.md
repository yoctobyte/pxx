---
slug: regression-test-sqlite-threads-aarch64-output-mismatch-untracked-since-08-29
track: A
prio: 55
type: regression
status: unfinished
owner: frankS
blocked-by: []
summary: "ANSWERED 2026-08-31: it is a TIMEOUT, not an output mismatch. The first full sweep carrying frankS's runner fix (fc5762a2f) says so in as many words -- `FAIL aarch64 (TIMED OUT after 120s; TESTMGR_TIME_SCALE=1.00) | partial output: []` at bebac33366f5, tier full, host seven. So the job never produced a wrong answer and there is no aarch64 miscompile to chase. CAUSE, confirmed by contrast: tools/run_sqlite_thread_test.sh applies TESTMGR_TIME_SCALE (line 63) but NOT TESTMGR_LOAD_SCALE, while all three sibling qemu runners compute their budget from BOTH (`t=20*s*l`). Time scale was 1.00 on seven, so the budget stayed at a hardcoded 120s while the full tier ran at high concurrency. Plexus needs 37s idle and 62s under a 12-way load, so 120s under seven's sweep concurrency is simply too tight. One-line fix, in Track T's tool -- handed to T, not applied here."
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

## ANSWERED — the resume condition fired, 2026-08-31 (frankA, Track A)

The ticket said *"the next full sweep on seven answers this"*. It has, and the
answer is unambiguous. Nothing was watching that prose trigger, so this was
picked up by hand off the Track A queue.

```
report   devdocs/progress/tstate/reports/20260831T023403Z-bebac33-seven.md
sha      bebac33366f5   tier full   host seven   verdict RED   wall 592.5s

test-sqlite-threads: FAIL aarch64 (TIMED OUT after 120s; TESTMGR_TIME_SCALE=1.00)
partial output: []
```

`bebac33366f5` is a descendant of the runner fix `fc5762a2f`
(`git merge-base --is-ancestor` — checked, and it is the *only* post-fix full
tier so far; the other post-fix report is tier `native`, which does not run this
job).

**So there is no aarch64 miscompile.** The job builds a 6.9 MB binary and then
runs out of clock. Every earlier report reading `FAIL aarch64 (output mismatch)`
was the old runner printing one line for two different events — exactly what
`fc5762a2f` was written to separate, working as intended on its first
full-tier outing.

### Cause: the load factor, which is this ticket's own Track T question

Confirmed by contrast rather than by reading one file:

| runner | budget |
| --- | --- |
| `run_c_conformance.sh` | `TESTMGR_TIME_SCALE` **and** `TESTMGR_LOAD_SCALE` |
| `run_fgl_corpus.sh` | `t=20*s*l`, both |
| `run_pascal_conformance.sh` | both |
| **`run_sqlite_thread_test.sh`** | **`TIME_SCALE` only** — `run_to=120` hardcoded at :32, scaled at :63 |

**A correction worth recording, because the wrong version is the obvious read:**
`SCALE` is *not* merely printed. Line 63 —
`run_to="${CSTT_RUN_TIMEOUT:-$(scaled "$run_to")}"` — really does apply it. I
had it as "read into a variable and only used in the message" and that is false.
What is missing is specifically `TESTMGR_LOAD_SCALE`, the live concurrency
factor (`cap/cores`) that testmgr exports and that the siblings multiply in.

On seven the time scale was **1.00**, so nothing stretched: seven is not slow,
it is *busy*. The budget stayed at 120s while a 592-second full tier ran around
it. Against frankS's plexus numbers — 37s idle, 62s under a 12-way load — a
120s ceiling under sweep concurrency is simply too tight, and the failure is a
load artifact rather than a defect in anything the job tests.

`run_c_conformance.sh:55-60` already documents this exact failure for its own
shards, naming `regression-testmgr-conformance-shard-timeout-under-load` "and
dups". This is another dup, in the one qemu runner that never got the fix.

### Handed to Track T — tool not edited

The change is one line and mirrors three siblings, but the *size* of the budget
is a claim about sweep economics (a longer inner timeout slows every full tier),
and that is T's to price, not Track A's. `tools/run_sqlite_thread_test.sh` is
**not edited here**.

Suggested shape, T's call:

```sh
scaled() { awk -v t="$1" -v s="$SCALE" -v l="${TESTMGR_LOAD_SCALE:-1}" \
  'BEGIN { v=t*s*l; printf "%d", (v < t ? t : v) }'; }
```

which keeps the existing floor and leaves `CSTT_RUN_TIMEOUT` as the override.

### What this does NOT clear, so it is not closed on my say-so

The job has been red since **2026-08-29**, and the load-scale gap explains a
timeout *under concurrency*. Whether every red in that stretch was the same
timeout is not established — the old runner could not tell the two apart, which
is the whole reason this ticket exists, so the earlier reports cannot be
re-read to answer it. **The next full sweep after the runner gains the load
factor is what confirms it**, and that is a real trigger this time: if it still
times out with the budget stretched, the timeout is genuine and there IS
something to chase.

**And the tracking gap in the body above is untouched by any of this** — the job
went red for two days with no auto-filed ticket. That half is still open and is
still worth T's glance.

