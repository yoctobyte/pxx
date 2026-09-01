---
prio: 70
track: T
blocked-by: []
status: done
---

> **Track T by default: no lane could be inferred** (the job reported no test source). This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 30 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: tools-devtest#00 red at 0c99981669b7 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T04:14:14Z
- **Test source:** unknown (see repro commands)

## Repro
`tools/testmgr.py --tier full --job 'tools-devtest#00'` at 0c99981669b7d19df37f3ec53646cf78a5c86c31

## Range
> **The named sha `0c99981669b7` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0c99981669b7`, last good `e46dbffaa80d`, 131 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
evtest.py
  tools-devtest: tools/twatch_cascade_range_devtest.py
  tools-devtest: tools/twatch_cascade_reason_devtest.py
  tools-devtest: tools/twatch_clone_clean_devtest.py
  tools-devtest: tools/twatch_close_stubs_devtest.py
  tools-devtest: tools/twatch_closure_status_devtest.py
  tools-devtest: tools/twatch_covering_devtest.py
  tools-devtest: tools/twatch_cross_currency_devtest.py
  tools-devtest: tools/twatch_diagnostics_devtest.py
  tools-devtest: tools/twatch_failing_step_devtest.py
  tools-devtest: tools/twatch_first_seen_devtest.py
  tools-devtest: tools/twatch_flaky_report_devtest.py
  tools-devtest: tools/twatch_full_commit_devtest.py
  tools-devtest: tools/twatch_gone_key_devtest.py
  tools-devtest: tools/twatch_heal_objectdb_devtest.py
  tools-devtest: tools/twatch_host_epoch_devtest.py
  tools-devtest: tools/twatch_idle_yield_devtest.py
  tools-devtest: tools/twatch_job_history_devtest.py
  tools-devtest: tools/twatch_no_testable_change_devtest.py
  tools-devtest: tools/twatch_opt_coverage_devtest.py
  tools-devtest: tools/twatch_pin_baseline_devtest.py
  tools-devtest: tools/twatch_pin_corroboration_devtest.py
  tools-devtest: tools/twatch_pin_straddle_devtest.py
  tools-devtest: tools/twatch_pin_verify_status_devtest.py
  tools-devtest: tools/twatch_pin_verify_why_devtest.py
  tools-devtest: tools/twatch_quiet_host_devtest.py
  tools-devtest: tools/twatch_refile_stub_devtest.py
  tools-devtest: tools/twatch_resume_devtest.py
  tools-devtest: tools/twatch_running_code_devtest.py
  tools-devtest: tools/twatch_skip_anchor_devtest.py
  tools-devtest: tools/twatch_stub_track_devtest.py
  tools-devtest: tools/twatch_timeout_staleness_devtest.py
  tools-devtest: tools/twatch_timeout_verdict_devtest.py
  tools-devtest: tools/twatch_verify_request_devtest.py
  tools-devtest: tools/verify_assertions_devtest.py
  tools-devtest: tools/whokilled_devtest.py
  tools-devtest: 114 green, 2 RED -- tools/exit_observable_devtest.py tools/progress_stale_edge_devtest.py

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Diagnosed and fixed — Track T, 2026-08-30

**The lane fallback was right, and for a checkable reason rather than by
default:** `tools-devtest#00` runs `tools/*devtest*.py`, so its subjects are
Track T's tooling by construction. It carries no `src` because the job's
sources are the scripts it enumerates, not a test file.

**The tail's last line is the only load-bearing one in it**, and it names both
reds: `114 green, 2 RED -- tools/exit_observable_devtest.py
tools/progress_stale_edge_devtest.py`. Everything above it is the job listing
its scripts. Worth noticing as a shape: this is the fpc-bootstrap case again —
a 2000-char tail that is 99% enumeration, where the one line that says anything
just barely fit inside the window.

Both were re-verified at HEAD (`b778c6078`) before anything was touched. **Both
still red.**

### 1. `exit_observable_devtest.py` — already filed, and still climbing

The stdout-only ratchet: 531 when armed at `f444a4a33` this morning, 548 when I
first saw it, 551 an hour later, **554 at HEAD**. Attributed and filed as
`bug-a-twenty-new-cross-target-rows-compare-stdout-without-the-exit-code`
(Track A — the rows are Makefile lines), with the gate-policy fork escalated as
`decide-what-should-a-shared-gate-do-when-its-watched-number-grows-from-normal-work`.
Not re-diagnosed here.

### 2. `progress_stale_edge_devtest.py` — TWO defects, and the first hid the second

**The cause is `65a63f0d2`** (*"STALE-PARK reads the PROSE half of the re-check
gap"*), which is inside this ticket's range. It rewrote the aperture note from
`reads FRONTMATTER only` to `reads FRONTMATTER; STALE-PARK reads PROSE …` and
left the devtest asserting the old literal. Proof rather than inference: the
exact string is present in `progress.py` at `65a63f0d2~1` and absent at
`65a63f0d2`.

**But the failure MESSAGE named something else entirely** — a `NEAR-DUP` about
`backlog/decide-posix-master-vs-fpc-named-master-for-the-socket-facades`, a
ticket this devtest has nothing to do with. The fixture was leaking: `_board()`
set `pg.PROG` to a throwaway tree, built the `Board`, and restored `PROG` **in a
`finally` before `.check()` ran**. `Board()` captures its tickets at
construction, so every assertion keyed on `self.by_status` kept reading the
fixture — while the `DUP-SLUG` / `NO-FRONTMATTER` / `NEAR-DUP` half of
`check()`, which walks `PROG / st` on disk at call time, read the **live repo**.
Half of `check()` saw the fixture and half saw master.

That is why the coordinator's warning was right for a reason neither of us had:
**a repro built from this message would have gone looking at two real backlog
tickets.** The message was true about a real thing and had nothing to do with
the red.

Same shape as the harness that deleted the pin it was measuring: a `finally`
that restores state before the thing under test has run.

### The fix, and the near-miss inside it

- `_board()` is **gone**, not left as a second entry point; `_check()` holds
  `PROG` across construction *and* `check()`.
- The fixture renders its **own** `BOARD.md` / `BOARD-brief.md` /
  `BOARD-<archived>.md` from its own tickets. `check()` regenerates and
  compares, so a fixture with no boards carries three `NO-BOARD` findings and
  one with placeholders carries three `STALE-BOARD` — either way the guard named
  *"including on a clean board"* was not running against a clean board. It is
  now: the whole output is the NOTE plus `board OK`.
- The aperture assertion is keyed on the note's identity and its two claims
  (`NOTE stale-edge`, that it names its aperture, that it disclaims the family)
  rather than on a wording that has already drifted once. A guard whose subject
  is *"the scan states its own reach"* must not fail because the reach got wider
  and was described more precisely.

**The near-miss, recorded because it nearly shipped:** repairing the wording
*removed the only thing that would ever have noticed the leak*. With the leak
reinstated and the wording fixed, this file reported **OK** — measured, not
supposed. The old guard caught the leak by accident, through a dumped `out` in
an assertion message. So a ninth guard now asserts the isolation directly and
state-independently: a synthetic near-duplicate pair in the fixture **is**
reported (proving the on-disk scan reaches the fixture at all), and on a clean
fixture **no finding names any file outside it** — which holds whether or not
master currently carries near-duplicates of its own. It does: six, right now.

**Gate:** 9 guards, 3 negative controls — suppressing the note reds the aperture
guard; reinstating the `PROG` leak reds the isolation guard with the real
repo's `decide-posix…` pair in the message; raising the NEAR-DUP threshold out
of reach reds the isolation guard's positive half, so it is not satisfied by a
scan that reads nothing.

`exit_observable_devtest.py` stays red, so `tools-devtest#00` stays red until
the Makefile rows land. That is one red job, not two, and it has its own ticket.

## Dated 2026-09-01: a window, and it has NEVER been green on seven

| | |
| --- | --- |
| red since | **2026-08-29T16:51:31Z**, at `154d1aa3f` |
| consecutive reds | **208**, with **zero** transitions in the whole archive |
| window | `e417731e9007..154d1aa3fba6` — **18 commits** |

Verified from `runs-seven.ndjson` (keys `date`/`sha`, seven only, sorted). This
is not a flapping job: across 208 runs it has never once come back green, so
**any green you see locally is a difference in how you ran it, not a fix.**

**The window is small enough to bisect directly** and that is the recommended
next step — the same method settled `exception_threads_race` tonight (frankB:
0/20 fail at `620989250^`, 20/20 at `620989250`).

**But look at what is in it.** The code half is largely a Rust topic-branch
merge series — `feat(rust): Option<T> as a monomorphized generic enum`,
`merge: master@4213b4b76 into the rust topic branch`, `Merge remote-tracking
branch 'origin/master' into rust`, and 5 merge commits in 18. A bisect across
merge commits does not behave like a bisect across a linear history, so use
`--first-parent` or expect to land on a merge that touches everything.

Raised separately with the owner: CLAUDE.md says **all tracks work on `master`,
no topic branches**, and Track R is marked experimental (X). Whether R has an
exception is his call, not this ticket's — noted here only because it is the
shape of the window and it changes how you bisect it.

Credit: frank-coordinator for the window and the method.

## Fixed at HEAD — 2026-09-01, frankZ. Three faults, and the third only existed once the first two were fixed.

Green: `tools-devtest#00 PASS guards 240.8s`, `testmgr: GREEN`, at binary
`b9fd008f89ef`.

**1. `tools/devtest_sync_fold.py` — the verdict depended on the developer's own
tree.** `sync.sh` runs its git half in `$ROOT` (`git rev-parse
--show-toplevel`) and its ticket half through `$(dirname "$0")/progress.py`,
which finds tickets relative to ITS OWN location. Invoked by absolute path from
a sandbox repo — which is exactly what this devtest does — it pushed THERE and
listed pending tickets from HERE, then failed with
`fill: no such file: devdocs/progress/done/...`. The check it failed was
`exits 0`. So the devtest was RED for me and green for anyone with no ticket
owing a citation.

Fixed by asserting the precondition — `[ ! -f "$f" ]` skips a path that is not
in the tree we are about to commit — rather than by re-rooting `progress.py`.
The re-rooting version was written first and is instructive: it turned all ten
of `tools/sync_citation_guard_devtest.py`'s guards into no-ops that still
printed PASS, because that devtest lifts `verify_citations_landed` out of
`sync.sh` and runs it against a stub `progress.py` in cwd, which only works
while the path is `$(dirname "$0")`-relative. One fix, two devtests, and the
second one caught the first.

**2. `tools/testmgr_pin_built_devtest.py` — one row put the pin in the native
tier.** `test/c_clearenv.c` was compiled with `$(PXX_STABLE)` under a note
saying "a crtl-source fix, so the pin compiles it from the tree" — true of
`./$(COMPILER)` as well, since either reads `lib/crtl` from the working tree,
so the pin bought nothing. What it cost is the invariant behind "a pin taken
during a native window is safe": `test-core` runs in native. Swapped to
`./$(COMPILER)` after verifying byte-for-byte identical output.

**3. The job then TIMED OUT, and that is the finding worth keeping.** The
runner counts failures and keeps going, so a red suite finishes in whatever
time it takes. `tools-devtest#00` had been red long enough that nobody had ever
measured a GREEN pass, and it was classed `unit` — a 90s budget against 207s of
real work. The hour the last failing guard was fixed, the job went from RED to
TIMEOUT. **A budget calibrated against a broken run punishes the fix.**

New `guards` class, 600s (207s tripled, the headroom `selfhost` uses), matched
on the `tools/*devtest*` glob rather than the target name so
`tools-devtest-sh` and the next one of that shape are classed right before
anyone notices. Adding it to `CLASSES` alone produced a `KeyError: 'guards'`
out of `write_live()` a minute into the run, because `CLASS_WEIGHT` is a second
table keyed by class — there is now a module-level assert that the two agree,
which costs nothing at import and names the cause instead of the symptom.

Re-laned from the `track: T` fallback: 1 and 3 really are Track T's tools, 2
was a Makefile row.
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
