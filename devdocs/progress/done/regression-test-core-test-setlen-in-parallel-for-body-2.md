---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_setlen_parfor26 "$(/tmp/test_setlen_parfor26)" "PARALLEL SETLEN OK total=8000"`. The job's own `src` (`test/test_setlen_in_parallel_for_body.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_setlen_in_parallel_for_body.pas at 456361785e34 in step 2/2, `tools/expect_same.sh test_setlen_parfor26 "$(/tmp/test_s` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T06:26:52Z
- **Test source:** test/test_setlen_in_parallel_for_body.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_setlen_parfor26 "$(/tmp/test_setlen_parfor26)" "PARALLEL SETLEN OK total=8000"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_setlen_in_parallel_for_body.pas'` at 456361785e3489b2a7ddd800bc216b5ec2bbe51f

## Range
> **The named sha `456361785e34` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `456361785e34`, last good `d28b77ce5d88`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2782012/test_setlen_parfor26  [code=126744B  data=5728B  bss=42612B  procs=277]
expect_same: MISMATCH [test_setlen_parfor26]
--- expected
+++ actual
@@ -1 +1 @@
-PARALLEL SETLEN OK total=8000
+PARALLEL SETLEN OK total=7944

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at d7aad6cd14a3 (tier full) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at 373deddb700b (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at d74c7fbe9ffe (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at afb7aa9da9c9 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at 2812ffacbe69 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at b8f7e6f2bb11 (tier full) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at 86126be99600 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at 243ff4a2942d (tier full) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-08-31 — the seven watcher saw `test-core#src:test/test_setlen_in_parallel_for_body.pas` GREEN at 2bdb3c4ef3f6 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-setlen-in-parallel-for-body-2`, not `regression-test-core-test-setlen-in-parallel-for-body`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## Does NOT reproduce on plexus, on EITHER compiler — 2026-09-02, frankZ

Run under the umbrella [[umbrella-one-full-tier-run-with-no-red-tier]], with
the recipe's own flags:

| binary | commit | runs | failures |
| --- | --- | --- | --- |
| `480d4584403c` (HEAD) | `ad55e4dcc` | 40 | **0** |
| `stable_linux_amd64/default/pinned` (v399) | 2026-08-19 | 30 | **0** |

Two independently built compilers, byte-different programs, 70 runs, no
failure. The tested sha `456361785e34` is also an upper bound rather than a cause —
the ticket's own banner says it touches no buildable file.

**This is half a finding and the residual belongs to Track T.** "Not
reproducible on plexus" does not answer "then why is it red on seven", and I
cannot answer that from here: **seven runs this job under full-matrix
parallelism and I ran it solo.** For a threading-adjacent program that is not
a detail, it is the most likely difference — the same shape as
`test_multithreading`, which needed no load to fail but whose rate moved with
it.

What would settle it, and what I am NOT claiming to have done: the same job on
seven, under load, at this sha. Left open and wired to the umbrella rather than
resolved, because a red nobody can reproduce is still a red in the tier that
decides whether a pin is green.

## MEASURED: this is a FLAKE, and the tstate archive says so outright (frankZ, 2026-09-02)

The earlier entry on this ticket said the failure does not reproduce here on
either compiler and named seven's full-matrix parallelism as the likeliest
difference. That was half a finding. Here is the other half, and it does not
depend on reproducing anything.

**Track T's own markers alternate.** Counting every tstate commit subject that
names `test_setlen_in_parallel_for_body`:

```
NEW-RED-bearing commits : 10
FIXED-bearing commits   : 10
total markers           : 20
all 20 markers land on 2026-08-31 alone
```

**A regression cannot be fixed and re-broken 10 times in one day.** That would
need 10 fixes and 10 breakages, on one host, across shas that mostly touch
docs and tickets. The only reading left is that the job's verdict is
**nondeterministic**, and the NEW-RED / FIXED pairs are the watcher faithfully
reporting a coin landing differently.

This is a second source that FAILS DIFFERENTLY from the local non-reproduction:
0-in-40 here is consistent with "rare flake" AND with "host-specific bug", and
cannot separate them. The alternating markers separate them — a host-specific
bug is stable on its host, and this is not stable on its host.

## What changes because of it

- **It is not a regression, so there is no cause in any commit range**, and the
  auto-filed range is not merely unnarrowed, it is meaningless. Nobody should
  bisect this.
- **The right work is to stabilise or quarantine the test, not to find a
  breaking commit** — and if the nondeterminism is a real race in the program
  under test rather than in the harness, that race is the ticket, at a much
  higher value than this one.
- **The residual owner does not change**: Track T, named above, now with a
  measurement instead of a hypothesis.

## Why it matters to the umbrella specifically

[[umbrella-one-full-tier-run-with-no-red-tier]] wants ONE full run with no RED
in any tier. **A test that flips on its own makes that a lottery** rather than a
consequence of fixing things: every arrival can be beaten by the fix rate and
the run still comes back red. Recorded there too.
- 2026-09-02 — CLOSED by claude-T on Track T dispatch. Re-verified at HEAD before diagnosing, per this stub's own banner: `tools/testmgr.py --tier native --job 'test-core#src:test/test_setlen_in_parallel_for_body.pas'` at `3e05d2946455` is **GREEN**. The regression is gone from the tree and the job is no longer in seven's `open_regressions`. No code change was needed for this ticket; what it cost was the re-verification.
