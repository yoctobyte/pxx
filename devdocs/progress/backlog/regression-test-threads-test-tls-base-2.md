---
prio: 70
track: A
summary: 'A REAL RACE IN THREAD-LOCAL STORAGE SETUP, RATED 2026-09-22: `test/test_tls_base.pas` prints `errors=2` instead of `errors=0`/`TLS OK` on **54 of 500** runs at `870f9f6e1` (compiler `06255ab1878c`, plexus) -- 10.8%, exact 95% CI 8.2-13.9% (Clopper-Pearson; RECORD THE ESTIMATOR BESIDE THE INTERVAL, because a reader who re-derives one with a different method gets a different number for no other reason). An earlier n=60 row gave 4/60 = 6.7%, exact CI 1.8-16.2% -- and its NORMAL-approximation interval of 0.4-13.0% was INVALID, np=4 against the np>=5 rule of thumb, with a 0.4% lower bound that is an artefact rather than a belief. The two exact intervals OVERLAP, so the rows agree and the point estimate did not really move; both are kept with their populations because a number whose interval spans a factor of thirty is not weak evidence, it is not evidence, and it looks identical to a strong one at a glance. WHAT IT DOES AND DOES NOT BLOCK, AND THE FIRST VERSION OF THIS SUMMARY HAD IT BACKWARDS: at 10.8% per attempt **EIGHT `full` TIERS IN NINE ARE GREEN ON THIS ROW**, so it does NOT block reaching a green -- it blocks TRUSTING one. The two readings prescribe opposite actions, which is why the error mattered: ''this blocks goal 1'' tells the owner to WAIT for a green that is already the likely outcome of any single run, when the true hazard is that **a green is easy to obtain and would be green BY LUCK, with a live threading race shipped inside it**. Goal 1 is a full green pin AS A RELEASE, so the defect is not tier colour -- it is that the colour stops carrying the information the release is meant to rest on. CLASS AND RETRIES: the job is class `unit` and `RUN_RETRY_CLASSES` is `{qemu, corpus, conformance, opt}`, so `unit` is DELIBERATELY single-shot and `p_report = p_attempt` -- nothing absorbs it. DO NOT MOVE THE ROW TO A RETRY CLASS: that converts a genuine nondeterminism bug into an invisible flake, which the selfhost half of testmgr''s own comment refuses in as many words (`a flake is a genuine nondeterminism bug to reseed, not retry`). The harness is behaving correctly; fix the race. RE-LANED T -> A: the auto-file''s `track: T` is an explicit FALLBACK because the failing step (`expect_same.sh`) names no owner, and the owner is the lane that built TLS (`done/feature-a-thread-local-storage-via-clone-settls`). NOT A REGRESSION FROM ANY RECENT COMMIT -- it is intermittent, therefore pre-existing; the body records where it was nearly pinned on a peer''s section-base commit that really was in the range. NOT AN ESCALATION YET, AND DO NOT MAKE IT ONE: nobody has attempted a fix, and asking the owner to rule on shipping a known race before any engineering has been tried is the expensive path for no reason. IF a fix is attempted and proves deep, THEN it becomes a one-sentence question in goal terms -- do we ship beta 0.1 with a threading race that reddens one tier in nine -- with the release window running to about 2026-09-30. ON PLEXUS THIS IS THE ONLY RED: the same `full` run is 4953 PASS / 1 FAIL / 0 SKIP / 0 FLAKY with skip_holes == 0, and the four rows that hold `full` red on borg all PASS here. WHAT WOULD RETIRE IT: a fix plus 200 consecutive clean local runs -- NOT one green tier, which at 10.8% is the expected outcome and carries almost no information.'
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

## 2026-09-22 (later still) — TWO CORRECTIONS TO THE SECTION ABOVE, BOTH FROM frankuser, AND THE FIRST ONE INVERTS ITS CONCLUSION

### 1. "Blocks goal 1" was backwards

At 10.8% per attempt, **8 `full` tiers in 9 are GREEN on this row.** So it does
**not** block reaching a green. It blocks *trusting* one.

**The two readings prescribe opposite actions**, which is the whole reason this
needed catching before it went to the owner:

| reading | what he would do |
| --- | --- |
| *"this row blocks goal 1"* | **wait** for a green that is already the likely outcome of any single run |
| the true statement | **distrust** a green, because it is easy to obtain and would be green *by luck* with a live threading race inside it |

**Goal 1 is a full green pin AS A RELEASE.** The defect is therefore not the
tier's colour — it is that the colour **stops carrying the information the
release is meant to rest on.** A pin whose green is 89% luck certifies nothing
about threading.

**The retirement condition in the section above was already right** — *a fix
plus 200 consecutive clean runs, not one green tier* — and that is precisely a
statement about **certifying a fix**, not about reaching a green. The headline
generalised it into a claim about *reachability*, and those are different
things. The correct standard survived; the sentence drawn from it did not.

### 2. The n=60 interval used an estimator that is invalid at n=60

Both earlier intervals were the **normal approximation**. For the 500-run row
that is fine (np = 54). For the 60-run row **np = 4**, below the np ≥ 5 rule of
thumb, and it produced a lower bound of **0.4%** — an artefact, not a belief
anyone holds. Exact (Clopper–Pearson):

| runs | fails | rate | normal 95% CI | **exact 95% CI** | np |
| --- | --- | --- | --- | --- | --- |
| 60 | 4 | 6.7% | 0.4 – 13.0% *(invalid)* | **1.8 – 16.2%** | 4 |
| 500 | 54 | 10.8% | 8.1 – 13.5% | **8.2 – 13.9%** | 54 |

**The conclusion is unchanged and slightly strengthened:** the small sample was
consistent with a rate *higher* than the normal approximation allowed, and the
two exact intervals **overlap** — so the rows agree and the point estimate did
not really move. Worth saying explicitly, because a reader comparing 6.7% to
10.8% may otherwise suspect a regression between them.

**RECORD THE ESTIMATOR BESIDE THE INTERVAL**, the same way this project already
records the population beside a count. Someone will re-derive one of these and
get a different number for no reason but the method, and — exactly like a bare
count — a bare interval is not refuted by a differing one, it is simply
unquotable.

### Not an escalation yet

Nobody has attempted a fix. Asking the owner to rule on shipping a known race
**before any engineering has been tried** is the expensive path for no reason —
it is laned to A and the release window runs to roughly **2026-09-30**. If a fix
is attempted and proves deep, *then* it becomes a one-sentence question in goal
terms: **do we ship beta 0.1 with a threading race that reddens one tier in
nine?** That sentence contains no implementation noun and is answerable in a
word, which is the test for whether it is his at all.
- 2026-09-22 — the borg watcher saw `test-threads#src:test/test_tls_base.pas` GREEN at b88b481c0b34 (tier full) and did NOT close this: the green is at the SAME sha the red was found at (`b88b481c0b34`), so no tree change separates them — the job returned two different answers about one tree, which is nondeterminism rather than evidence of a fix. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
