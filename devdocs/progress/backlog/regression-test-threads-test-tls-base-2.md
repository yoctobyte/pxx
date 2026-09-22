---
prio: 70
track: A
summary: 'A REAL RACE IN THREAD-LOCAL STORAGE SETUP, RATED 2026-09-22: `test/test_tls_base.pas` prints `errors=2` instead of `errors=0`/`TLS OK` on **54 of 500** runs at `870f9f6e1` (compiler `06255ab1878c`, plexus) -- 10.8%, 95% CI 8.1-13.5%. An earlier n=60 row gave 4/60 = 6.7% with a CI of 0.4-13.0%; BOTH ROWS ARE KEPT WITH THEIR POPULATIONS because the small one supports no decision and is not refuted by the large one. THIS BLOCKS GOAL 1 ON ITS OWN: the job is class `unit`, `RUN_RETRY_CLASSES` is `{qemu, corpus, conformance, opt}`, so `unit` is DELIBERATELY single-shot and `p_report = p_attempt` -- this single row turns roughly ONE `full` TIER IN NINE red with nothing absorbing it. DO NOT FIX IT BY MOVING THE ROW TO A RETRY CLASS: that converts a genuine nondeterminism bug into an invisible flake, which the selfhost half of testmgr''s own comment refuses in as many words (`a flake is a genuine nondeterminism bug to reseed, not retry`). The harness is behaving correctly; fix the race. RE-LANED T -> A: the auto-file''s `track: T` is an explicit FALLBACK because the failing step (`expect_same.sh`) names no owner, and the owner is the lane that built TLS (`done/feature-a-thread-local-storage-via-clone-settls`). NOT A REGRESSION FROM ANY RECENT COMMIT -- it is intermittent, therefore pre-existing; a near-miss is recorded in the body where it was nearly pinned on a peer''s section-base commit that really was in the range. ON PLEXUS THIS IS THE ONLY RED: the same `full` run is 4953 PASS / 1 FAIL / 0 SKIP / 0 FLAKY with skip_holes == 0, and the four rows that hold `full` red on borg all PASS here. WHAT WOULD RETIRE IT: a fix plus 200 consecutive clean local runs -- NOT one green tier, which at 10.8% is the expected outcome and carries almost no information.'
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

## 2026-09-22 (later) — RE-RATED AT n=500: **10.8%**, CI **8.1–13.5%**, i.e. ONE FULL TIER IN NINE

**Carry the interval, not the point** — frankuser's correction, and it was right
in the direction that matters. Both rows, each with its population, because a
later disagreement is not a refutation when neither denominator was recorded:

| runs | fails | rate | 95% CI | reddens a tier |
| --- | --- | --- | --- | --- |
| 60 | 4 | 6.7% | 0.4 – 13.0% | 1 in 15 (1 in 8 … 1 in 282) |
| **500** | **54** | **10.8%** | **8.1 – 13.5%** | **1 in 9 (1 in 7 … 1 in 12)** |

Same binary, same tree (`870f9f6e1`, compiler `06255ab1878c`), same box, minutes
apart. **The n=60 point estimate was LOW and its interval was nearly useless** —
"somewhere between 1 run in 8 and 1 run in 282" supports no decision at all. At
n=500 the answer is sharp and it is **not** a nuisance figure.

**WHY THAT DECIDES SOMETHING.** `unit` is a single-shot class, so
`p_report = p_attempt`: this one row alone turns roughly **one `full` tier in
nine** red, with nothing absorbing it. A release-grade green is not a matter of
waiting for a quiet box — at 10.8% it is a coin that comes up red about as often
as a working week has days. **This blocks goal 1's "full green pin as release"
on its own**, independent of every other row.

## The near-miss, recorded because it is evidence the rule works

**I nearly attributed this to another seat's commit.** The row passed in one
`full` run and failed in the next, and between them a Track A change titled
*"a runtime witness for every section base"* had arrived in a pull. **A TLS base
and a section base sound like the same thing**, the timing was perfect, and the
mechanism story wrote itself. `git merge-base --is-ancestor` confirmed the
commit was genuinely in the range — so the range check did not exonerate it,
it just stopped the story being told before the row had been run twice. **Sixty
local runs settled it in under a minute: intermittent, therefore pre-existing,
therefore nobody's commit.** CLAUDE.md's *attribute a tier delta to a RANGE
before attributing it to yourself* has a third corner — attributing it to a
PEER — and that is the one that also damages someone else's record.

## And on this host, nothing else is red

Measured in the same `full` run (plexus, qemu 10.2.1, `870f9f6e1`,
4953 PASS / 1 FAIL / 0 SKIP / 0 FLAKY): the four rows that hold `full` red on
borg — `demos#00`, `lib-test#00` (`crtl_reachability.py`),
`test-pascal-conformance#shard3/6` and `test-aarch64#00` (the C-ABI prologue
probe) — **all PASS here.** So **this race is the only thing between plexus and
a green `full`**, and borg's remaining red set is environmental to borg.

*(Method note, because it nearly went wrong again: `compiler_srchash.sh` matches
**74** rows in this tier as a shared PREREQUISITE. The aarch64 subject is
`test-aarch64#00`. A prerequisite is not a row.)*
