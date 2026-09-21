---
prio: 70
track: A
summary: "ROOT-CAUSED AND FIXED (12d6c86f0). NOT a timing flake and NOT a short timeout: the heap lock's sigaltstack bounds test -- the thing that tells an ASYNC re-entry (a signal handler, which runs on the thread it interrupted and so presents the owner's own tid) from a SYNC one -- WAS NEVER EMITTED, so a handler was granted the lock on a bare tid match and allocated inside a half-updated heap. THE MECHANISM IS A CALL SITE THAT KEPT ITS NAME AND LOST ITS GUARANTEE, and that is the shape to look for again: EmitHeapLockStubs calls EnsureSignalBss with a comment saying it is called 'only to fix the ORDER, so the bounds are allocated before this stub reads them', which was true until 16ebf18ce (2026-09-18) split BSS_SIG_ALTSTK/_ALTSS out into EnsureSignalAltStack to save 32KB of BSS -- a correct fix that left this reader depending on an allocation its callee no longer performed. BSS_SIG_ALTSTK was then 0 at prologue time and the `<> 0` guard silently emitted nothing. It would spring again for ANY prologue-time reader of a slot whose allocator moves later; the general tell is a guard of the form `if <slot> <> 0` whose false arm is correct-looking silence. Fix moves the reservation earlier under the predicate copied verbatim from EmitSignalRuntimeForTarget, so it costs ZERO additional BSS and preserves 16ebf18ce. Verified in the emitted bytes and by interleaved A/B, N=8 pairs: broken 8/8 hang at 90s vs fixed 8/8 exit 212 in 4.35-4.63s, the fixed arm succeeding at loads 6.21-11.23 after the broken arm hung at 5.64-8.60. STILL OPEN and NOT closed by this: the per-thread residual -- sigaltstack is per-thread, only the installing thread registers one, so a handler taken on a clone(2) thread runs on that thread's own stack, passes the bounds check and is still granted."
status: done
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

## 2026-09-21 — ROOT CAUSE, FIX, AND THE TWO INSTRUMENTS THAT COULD NOT SEE IT

**Fixed in `12d6c86f0`.** The section above localised this to the reentrant
heap-lock layer and said so as a *candidate*. It is now established, and the
mechanism is not the one that section guessed at.

### The cause, read out of the emitted bytes

The sigaltstack bounds test is **not emitted at all**. The grant path at the
broken HEAD reads:

    400230:  cmp %rsi,[BSS_HEAP_OWNER]
    400237:  jne 0x40023b          ; -> .acquire
    400239:  jmp 0x400257          ; -> .bump   GRANTED, nothing in between

`EmitHeapLockStubs` guards the whole async test with `if BSS_SIG_ALTSTK <> 0`,
and `BSS_SIG_ALTSTK` is 0 when the prologue runs. The call site above it says
`EnsureSignalBss;` with a comment promising the bounds are allocated first —
true until `16ebf18ce` (2026-09-18) split `BSS_SIG_ALTSTK`/`_ALTSS` out into
`EnsureSignalAltStack`, correctly, to stop reserving 32 KB in images that can
never install a handler. **The call kept its spelling and its comment and lost
its guarantee.** No error, no warning, a working compiler, and the self-host
fixedpoint converges either way.

So this is the 2026-09-16 defect restored verbatim, two days after it was
fixed, without anyone editing the function that fixes it.

**A NOTE ON THE TRAP NEXT TO IT:** there *is* a stack-bounds test in the broken
binary, at 0x400206, and it is the wrong one — that is the TLS tid-safety check
(slots 2/3, LO/HI). Two "is rsp within bounds" tests, and the one still present
is not the one that matters. Reading the disassembly for "a bounds check" finds
it and concludes the fix is in place.

### Evidence

Interleaved A/B, HEAD vs `-dPXX_NO_REENTRANT_HEAPLOCK`, alternating on one box
so drifting load hits both arms, N=8 pairs per table:

| build | head arm | nore arm | head loads |
| --- | --- | --- | --- |
| broken (`ce18a30c8`) | **8/8 HANG**, 90.0s, no message | 8/8 exit 212, 2.5–4.0s | 5.64–8.60 |
| fixed (`12d6c86f0`) | **8/8 exit 212**, 4.35–4.63s | 8/8 exit 212, 2.6–3.2s | 6.21–11.23 |

The fixed arm diagnoses at loads **above every load at which the broken arm
hung**. That is the opposite of what a loaded-box timeout predicts and retires
the flake reading on a second axis, independent of the duration argument above.

Build-time guard added beside the fix; positive control verified by deleting
the new call, rebuilding, and confirming the refusal fires and emits no binary.

**Zero BSS cost.** The predicate is copied verbatim from
`EmitSignalRuntimeForTarget` (`(not NoSignals) and TargetHasSignalRuntime`) and
`EnsureSignalAltStack` is idempotent, so any program satisfying it already got
the reservation — this only moves it ahead of the prologue that reads it.
`16ebf18ce`'s saving is preserved for `--no-signals` and signal-less targets.

### Two instruments that answered confidently and wrong

Recorded because both are reusable mistakes, not incidents.

**1. gdb cannot observe this bug in either disposition, and gives a different
wrong answer in each.** `tools/pxx_pc_sample.py` reported 100% of 18 samples at
one PC, identical across three runs — `PalThreadCreate+0x3b5`, which is a real
name for that address, not a map-gap artefact. It was still meaningless: gdb's
default disposition for SIGUSR1 is *stop*, and SIGUSR1 is the signal this test
fires 2,000,000 times, so gdb was halting the process on every `tkill` and
serialising the race under test. Set `handle SIGUSR1 nostop noprint pass` and
the program runs to completion printing `NOT REACHED: the handler never collided
with the lock` — a **third** outcome, neither 212 nor hang. Catch the subject's
signal and you serialise it; pass it and ptrace overhead moves the collision
window. This is the mirror of the hazard already in that tool's header (the
sampler *injecting* the subject's signal): the subject's signal must also be
explicitly passed, and for a race bug even that is not enough.

**2. `/proc/<tid>/syscall` is empty here, so it is not a second source.** It was
reached for precisely because it fails differently from gdb, which is the right
instinct; it returned `[]` for a running task and answered nothing. What `/proc`
*did* establish is real and independent: one thread, state `R`, utime
3808→8453 jiffies over 84 s — a full core in userspace, zero syscalls.

### Populations, including one that does not resolve

Per the rule that a bare count is not re-derivable: the hang **rate** at the
broken HEAD was measured twice on the same binary (sha `f8fcf4f9…`, built
08:29:08) with two harnesses that are the same method line for line, minutes
apart: **5 of 8 diagnosing** (08:34–08:39) and **0 of 8** (08:39–08:51). Both
rows stand; neither replaces the other. The obvious explanation is false — a
peer's six-build stretch began 08:45:44, after three of the second run's hangs
had already landed, so it cannot be the cause. **Unexplained.** It does not
bear on the fix: the A/B is interleaved, so whatever moves the rate moves both
arms, and the arm contrast is 8/8 vs 8/8 in both directions.

### What this does NOT close

The per-thread residual, named in `EmitHeapLockStubs`'s own comment and untouched
here: sigaltstack is per-thread and only the installing thread registers one, so
a handler taken on a `clone(2)` thread runs on that thread's own stack, passes
the bounds check, and is still granted. This test installs on main, which is what
the fix restores.
- 2026-09-21 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
