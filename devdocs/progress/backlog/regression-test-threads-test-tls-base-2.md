---
prio: 70
track: A
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 27 is `tools/expect_same.sh test_tls_base26 "$(/tmp/test_tls_base26)" "$(printf 'errors=0\nTLS OK')"`. The job's own `src` (`test/test_tls_base.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_tls_base`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_tls_base.pas at 165473bf9e30 in step 2/27, `tools/expect_same.sh test_tls_base26 "$(/tmp/test_tls_base26)" "$(printf 'errors=0\nTLS OK')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-19T13:07:41Z
- **Test source:** test/test_tls_base.pas tools/expect_same.sh
- **Failing step:** line 2 of 27 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_tls_base26 "$(/tmp/test_tls_base26)" "$(printf 'errors=0\nTLS OK')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-threads#src:test/test_tls_base.pas'` at 165473bf9e3059c1569928abe27c357860895aee

## Range
> **The named sha `165473bf9e30` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `165473bf9e30`, last good `f648c28e35e2`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1297515/test_tls_base26  [code=177462B  data=7568B  bss=62308B  procs=631  codeseg=179936B]
expect_same: MISMATCH [test_tls_base26]
--- expected
+++ actual
@@ -1,2 +1 @@
-errors=0
-TLS OK
+errors=2

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-19 — the borg watcher saw `test-threads#src:test/test_tls_base.pas` GREEN at 7fc84cc198ee (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-tls-base-2`, not `regression-test-threads-test-tls-base`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-20 — the borg watcher saw `test-threads#src:test/test_tls_base.pas` GREEN at bd12bfab03e7 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-tls-base-2`, not `regression-test-threads-test-tls-base`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-22 — the borg watcher saw `test-threads#src:test/test_tls_base.pas` GREEN at fa50b308bf99 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-tls-base-2`, not `regression-test-threads-test-tls-base`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

---

## 2026-09-22 (frankh-c0) — MEASURED AT HEAD ON PLEXUS: A REAL RACE, ~6.7% PER ATTEMPT, AND THE HARNESS IS RIGHT TO REDDEN ON IT

**Reproduced and rated.** `./compiler/pascal26 --threadsafe test/test_tls_base.pas`
then running the binary, at `870f9f6e1`, compiler `06255ab1878c`, plexus:

```
60 consecutive runs, otherwise-idle box:  4 failures  (6.7%)
failing output:  errors=2        passing output:  errors=0 / TLS OK
```

Deterministic reproduction is **not** available — it passed 3, failed the 4th,
then passed 30 more. So this is a genuine intermittent, not a stale expectation.

**IT REDDENED A `full` TIER TODAY** (plexus, 4953 PASS / 1 FAIL / 0 SKIP / 0
FLAKY, 1481.6s) as the single red, which is what brought me here.

### RE-LANED: this is NOT Track T

The auto-file header says `track: T` is a FALLBACK because the failing step
named no owner, and says outright to re-lane before working it. **The owner is
the lane that built TLS**: `done/feature-a-thread-local-storage-via-clone-settls.md`.
The failing step is `expect_same.sh` only because that is where the comparison
lives; the defect is in thread-local storage setup, which is **Track A**.

### AND DO NOT "FIX" THIS BY GIVING THE ROW RETRIES — THE SINGLE-SHOT POLICY IS CORRECT HERE

This was my first instinct and it is wrong, so it is written down. `testmgr`'s
`RUN_RETRY_CLASSES` is `{qemu, corpus, conformance, opt}` and **`unit` is
deliberately single-shot**, on a stated premise:

> *"Deterministic classes — `unit` (build+run of a fixed program) and
> `selfhost` ... stay SINGLE-SHOT. A real red fails every attempt, so
> confirm-retry never hides one."*

**The premise is false for this row** — a threading test in the `unit` class is
not a build+run of a deterministic program — and the tempting repair is to move
it into a retry class. **That would be a compiler-appeasement workaround**: it
would convert a real nondeterminism bug into an invisible flake, which is
precisely what the `selfhost` half of that same comment refuses (*"a flake is a
genuine nondeterminism bug to reseed, not retry"*). The harness is surfacing a
real race. Fix the race.

**THE ARITHMETIC CONSEQUENCE, WHICH CORRECTS SOMETHING I RELAYED EARLIER
TONIGHT.** I costed per-attempt flake rates into per-report ones as
`p_report = p_attempt^3`, from testmgr's three attempts. **That only holds for
the four retry classes.** For a `unit` row it is `p_report = p_attempt`, so this
single row reddens a whole tier on roughly **1 run in 15** with nothing
absorbing it — three orders of magnitude worse than the `p^3` model implies, and
the model was wrong by class rather than by arithmetic.

### What would retire this

A `full` tier green with this row passing, plus 200 consecutive local runs
clean. **Do not retire it on one green run**: at 6.7% a single pass is the
expected outcome and carries almost no information.
