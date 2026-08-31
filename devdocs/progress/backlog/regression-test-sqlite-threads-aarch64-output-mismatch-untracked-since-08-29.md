---
slug: regression-test-sqlite-threads-aarch64-output-mismatch-untracked-since-08-29
track: A
prio: 55
type: regression
status: new
owner: ""
blocked-by: []
summary: "`test-sqlite-threads-aarch64` has been RED in every full-tier sweep since 2026-08-29 and NOTHING TRACKS IT -- no ticket in any folder, though this job has been auto-filed by twatch and fixed TWICE before. It builds fine (6.9MB binary, exit 0) and then reports `FAIL aarch64 (output mismatch)`, so it is a wrong ANSWER, not a build break. Filed by hand after checking it was not mine: it was already red at 2026-08-30T02:54Z under compiler 67f47b5bc540, 25 hours before the aarch64 signal change landed. NOT REPRODUCED LOCALLY -- this checkout has no sqlite amalgamation, so the script SKIPs here; whoever takes it needs library_candidates/sqlite."
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
