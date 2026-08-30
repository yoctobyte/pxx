---
prio: 70
track: T
blocked-by: []
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
