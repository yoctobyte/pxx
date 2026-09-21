---
prio: 70
track: A
summary: "NOT a timing flake and NOT a too-short timeout -- the ticket said so from 2026-09-18 to 2026-09-21 and the number that settles it had never been taken. A PASSING run of this job is 4.22-4.53s against a 60s limit (13x margin); a failing run pins the wall at 60s AND at 90s. Bimodal, nothing in between, 8 runs, loads 5.1-8.66 -- and the TWO HIGHEST-LOAD runs both PASSED, which is the opposite of what a loaded-box timeout predicts. The phase-1 control prints contention-workers-finished=12 in every single run, so twelve threads complete the heaviest legitimate contention and the failure is entirely phase 2, the deliberate collision that must be NAMED. Re-laned T->A: the asserted exit code 212 is produced by a COMPILER-EMITTED stub (ir_codegen.inc:3779 interns the message and emits the spin budget, the .dead arm and exit_group(212)); nothing in tools/ decides it, and track:T was the auto-filer's documented fallback. The regression is in RELIABILITY and the parent ticket records the baseline: bug-a-the-threadsafe-allocator-is-not-async-signal-safe logs option 3 landing 2026-09-02 as 'measured 1.9s from the collision, 6 runs of 6'. It now fires 5 of 8. Leading candidate NOT yet established: the reentrant heap-lock layer grants the lock on a tid match and a signal handler runs on the thread it interrupted, which was measured with this exact symptom on 2026-09-16 and fixed by a sigaltstack bounds test whose own comment names an unclosed per-thread residual."
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 13 is `out=$(timeout 60 /tmp/test_ts_hl_diag26 2>&1); rc=$?; \ tools/expect_same.sh test_ts_hl_diag26_exit "$rc" "212" && \ too`. The job's own `src` (`test/test_threadsafe_heap_lock_deadlock_diag.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_threadsafe_heap_lock_deadlock_diag`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas at aa43f495ab87 in step 2/13, `out=$(timeout 60 /tmp/test_ts_hl_diag26 2>&1); rc=$?; \ tools/expect_same.sh test_ts_hl_diag26_exit "$rc" "212" && \ to…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-14T00:36:34Z
- **Test source:** test/test_threadsafe_heap_lock_deadlock_diag.pas tools/expect_same.sh
- **Failing step:** line 2 of 13 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  out=$(timeout 60 /tmp/test_ts_hl_diag26 2>&1); rc=$?; \ tools/expect_same.sh test_ts_hl_diag26_exit "$rc" "212" && \ tools/expect_same.sh test_ts_hl_diag26_control "$(printf '%s\n' "$out" | sed -n 1p)" "contention-workers-finished=12" && \ tools/expect_same.sh test_ts_hl_diag26_named "$(printf '%s\n
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas'` at aa43f495ab8788a6f3fbef0485a902310cf29d7c

## Range
bad `aa43f495ab87`, last good `1e3e9a0b95d0`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2383160/test_ts_hl_diag26  [code=179992B  data=9664B  bss=55676B  procs=640]
expect_same: MISMATCH [test_ts_hl_diag26_exit]
--- expected
+++ actual
@@ -1 +1 @@
-212
+124

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 369f962af9e5 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 8eec0021138c (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at b44571a727b2 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at cf374e381b5d (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at accb99f3c59b (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 1fa5bc5e334c (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at f09f6bcde929 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 582545aef690 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-14 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at a2861701f1a0 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-15 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 32a0a421a292 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-15 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 2dc0d6878b27 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-15 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at f7a745e876ef (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-15 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 827fabcc7d6d (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-15 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 14b9417631c6 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-15 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 1416e94114df (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-15 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 1073d96840ab (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-15 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 3a91d13f1dec (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-16 frankuser (Fable) — borg's NEW-RED at 693c910b4 (rc 124) is NOT in the 3a91d13f1..693c910b4 range: on plexus the test hangs 5/5 (three runs built by HEAD's compiler 4bc890e6604c0103, two by pin v410, code 179992B both), line 1 `contention-workers-finished=12` prints and line 2 (the 212 diagnostic) never does, `timeout 60` kills it. The only compiler change in the range is NilPy-frontend-only (7bf3860e0). Intermittent on borg, deterministic on plexus — the watchdog that should raise 212 never fires here. Lane: A (threads runtime), not N.
- 2026-09-16 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at e572bd42501e (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-16 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at ab2ebb31ea14 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-18 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 9f67753a16d6 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-18 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 95b92d92023e (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-18 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 7f86a12a6628 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-18 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 91ba5968354b (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## 2026-09-18 night watch — THIS JOB CANNOT SUPPORT A BISECT, AND ITS CURRENT `bad` IS NOT A LEAD

**Do not audit `c44fa2642` on the strength of this ticket.** `twatch --status`
now reports this job as `bad=c44fa26429e9 (1 in range)` — narrowed 3 -> 1 by idle
bisect, and with none of the *"bad touches NO buildable file"* caveat the other
six open regressions carry, so it reads like the one real lead on the board. It
is not, and three independent things say so.

**1. The failure is a TIMEOUT, not a wrong answer.** The log tail expects `212`
and gets **`124`** — the exit status `timeout` itself returns when it kills the
child. The recipe is `out=$(timeout 60 /tmp/test_ts_hl_diag26 ...)`, and the
subject is a lock-contention diagnostic that finishes **twelve** workers. So the
assertion that fails is not the diagnostic's verdict; it is whether the box got
through the contention inside sixty seconds. borg spent 2026-09-18 running full
tiers, an opt sweep, a bench and idle bisects.

**2. The same tree gives OPPOSITE verdicts in two tiers — three times.** From
the tstate commits, each pair one sha:
`91ba5968354b` NEW-RED (full) / FIXED (native); `7f86a12a6628` NEW-RED (full) /
FIXED (native); `95b92d92023e` NEW-RED (full) / FIXED (native). **A defect that
is present and absent at one sha is not a defect at that sha**, it is a race
against a clock, and the full tier is simply the busier neighbour.

**3. The `bad` sha MIGRATED, which is the tell a flapping job leaves and a real
one cannot.** This ticket was auto-filed on 2026-09-14 with bad `aa43f495ab87`,
1 commit in range. Four days later the same job's bisect has walked to
`c44fa26429e9` — a 330-line ELF-writer change (`feat(A,S): ESP-IDF objects carry
string literals in a read-only .rodata`) with no path to heap-lock contention
timing. **A stable regression bisects once and stays put.** Bisection assumes a
monotone good->bad boundary; a timing flake has none, so the search terminates on
whichever commit it happened to sample red and reports it with full confidence.

**What is therefore NOT established, said plainly:** that there is no real race
here. This says the INSTRUMENT cannot locate one, not that the subject is clean —
the job may well be guarding something worth guarding. What is established is
that its `bad` sha is an artefact of sampling and must not be read as an
attribution against any commit.

**RESIDUAL QUESTION, and it needs an owner (Track T):** does this job get a
longer/adaptive timeout, get pinned to an unloaded host, or get marked
non-bisectable so the watcher stops minting attributions from it? Left
unassigned deliberately — the fleet was wound down on 2026-09-18 and this tick is
a watch, not a dispatch. Flagged to the owner the same night.
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at a330bf12fed7 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 5db5e4620a1d (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 326bfc569552 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at fada42022187 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 523c10e42d90 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at e8a98c976991 (tier full) and did NOT close this: the green is at the SAME sha the red was found at (`e8a98c976991`), so no tree change separates them — the job returned two different answers about one tree, which is nondeterminism rather than evidence of a fix. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 26a1557fef17 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at ff2d50a2bde9 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 2c09be089d8d (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at c5353ea7616c (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 1bdaba382d42 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at d6ab05ec55b2 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 2723029f4125 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 52c44f85830e (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at ab5bf4228141 (tier full) and did NOT close this: the green is at the SAME sha the red was found at (`ab5bf4228141`), so no tree change separates them — the job returned two different answers about one tree, which is nondeterminism rather than evidence of a fix. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 472a58bb93e3 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at df19c8d95807 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at f2bcb5ecb43b (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at fae99f4a70b1 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 8318e225854d (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 606d79c053ff (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas` GREEN at 44728b431d89 (tier full) and did NOT close this: this is a repeat stub (`regression-test-threads-test-threadsafe-heap-lock-deadlock-diag-2`, not `regression-test-threads-test-threadsafe-heap-lock-deadlock-diag`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## 2026-09-21 — RE-LANED TO A, AND THE FLAKE READING IS REFUTED ON THE DURATION AXIS

**Lane: A, not T.** `track: T` was the auto-filer's documented fallback and the
ticket says so in its own header. The failing assertion is an exit code that a
**compiler-emitted stub** produces: `compiler/ir_codegen.inc:3779` interns
`Runtime error 212: the heap lock was never released.` and emits the spin
budget, the `.dead` arm, the `sys_write` and the `exit_group(212)`. Nothing in
`tools/` decides this outcome. The test source named in the slug is what the job
compiles, which the header also warns about.

**THE 2026-09-18 CONCLUSION IS REFUTED, AND IT WAS A GOOD CONCLUSION FROM THE
EVIDENCE IT HAD.** That watch read the failure as a race against a clock —
`rc=124` is `timeout`'s own exit code, so what fails is "did the box get through
in sixty seconds". It then reasoned, correctly, that a defect present and absent
at one sha is not a defect at that sha. **What nobody did was measure how long a
PASSING run takes**, and that single number decides it:

    HEAD, --threadsafe -dPXX_NO_HEAP_MAG, load recorded per run

      N=8, one binary, alternating nothing, loads 5.10 -> 8.66 per run
        pass  rc=212   4.22  4.32  4.43  4.53  4.53 s     (5 of 8)
        hang  rc=124  90.04 90.11 90.11 s                 (3 of 8)
      earlier N=5 at a 60 s limit: rc=212 4.43 s once, rc=124 60.08-60.10 s x4

      THE TWO HIGHEST-LOAD RUNS BOTH PASSED (load 7.93 and 8.66, 4.22 s and
      4.32 s). If load caused the timeout those are the two that should have
      failed. Load does not order this outcome.

**A passing run is 4.4–4.5 s against a 60 s limit — a 13x margin — and a failing
run pins the wall at 60 s AND at 90 s.** The distribution is bimodal with
nothing in between. A box too slow produces 30 s, 50 s, 58 s creeping toward the
limit; this produces 4.5 s or never. **No load turns 4.5 into 90.** Raising the
timeout is therefore not the fix and would only make the job slower to fail.

**The phase-1 control passes in every run**, printing
`contention-workers-finished=12`. So twelve threads complete the heaviest
legitimate contention and the failure is entirely in phase 2 — the deliberate
collision that must be NAMED.

**There is a recorded baseline for how often it should fire, and it is in the
parent ticket.** `bug-a-the-threadsafe-allocator-is-not-async-signal-safe`
records option 3 landing on 2026-09-02 as *"measured 1.9s from the collision,
6 runs of 6"*. So the diagnosis used to be reliable and is now intermittent.
**That is the regression** — not a wrong answer, and not a slow box.

## What is NOT established

That the mechanism is the reentrant layer. It is the leading candidate and the
code says why: `EmitHeapLockStubs` grants the lock when the caller's tid equals
`BSS_HEAP_OWNER`, and **a signal handler runs on the thread it interrupted**, so
it presents exactly that tid. That was measured on 2026-09-16 with this same
symptom — *"the deadlock probe HANGS to the harness timeout (rc=124, no
message)"* — and fixed by testing whether `rsp` lies inside the sigaltstack
bounds, which separates an interrupt from a call. The fix is present at HEAD.
**Its own comment names an unclosed residual:** sigaltstack is per-thread and
only the installing thread registers one.

Two arms settle it: `-dPXX_NO_REENTRANT_HEAPLOCK`, which the code says restores
the 212, and a PC sample of a hanging run to see where it is parked. Both are
running as this lands; the result goes below rather than replacing this.
