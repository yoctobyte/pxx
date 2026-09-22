---
slug: bug-t-native-s-red-is-one-row-and-full-s-is-ninety-four-so-they-are-different-problems
track: T
prio: 70
type: bug
status: backlog-tools
found: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: "`umbrella-one-full-tier-run-with-no-red-tier` closed 2026-09-07 saying in its own last line `If it regresses, that is a new ticket`. IT HAS: measured at pinned ref `ad275f0d96c3` over all 2898 tstate reports in the tree, the last `full` GREEN is 2026-09-09T08:21:39Z and the last `native` GREEN is 2026-09-11T16:28:30Z. THE USEFUL FINDING IS NOT THAT BOTH ARE RED -- IT IS THAT THEY ARE RED IN COMPLETELY DIFFERENT SHAPES, which no aggregate verdict can say and which decides how much work `full green expected` actually is. NATIVE IS A FINISHING JOB: 33 distinct rows ever red in 306 RED reports since its last green, and `test-core#src:test/c_crtl_wait.c` is red in 306 of 306; clearing that one row alone would have made 42% of those reports GREEN, four rows reaches 73% and eight reaches 90%. FULL IS BROAD: 129 distinct rows over 313 RED reports, median 6 per report, and the best eight rows together reach only 32% -- a long tail, not a few chronic blockers. So native is a finishing job and full is not, and quoting one tier's difficulty for the other is the error this ticket exists to prevent. Every one of the top rows ALREADY HAS AN OPEN TICKET (c_crtl_wait, crtl_reachability, threadsafe_heap_lock_deadlock_diag, crtl_atexit, compiler_srchash), so this state is UN-FINISHED, not un-triaged, and the fix is not more filing. SETTLED FOR `native` 2026-09-22: A FULL NATIVE TIER AT HEAD IS GREEN ON A NON-BORG HOST, 2580/2580 (plexus, tree e5408b0e6, compiler 06255ab1878c, frozen-tree guard green, 417.3s). So the never-green record is NOT a statement about the tree, and the fear that borg's chronic rows and seven's chronic rows were two disjoint populations needing separate campaigns is REFUTED -- both sets pass on one machine in one run. MY RECORDED PREDICTION WAS `probably RED` AND WAS WRONG. BUT THE ONE ROW THIS TICKET WAS BUILT AROUND FLAKED INSIDE THAT GREEN: test/c_crtl_wait.c failed attempt 1 of 3 and passed on attempt 2, so WITHOUT THE FLAKE GUARD THIS TIER WOULD HAVE BEEN RED ON EXACTLY BORG'S ROW, and the earlier single-job PASS was one draw from a nondeterministic test. Across three hosts that row is 9/638 on seven, flaky on plexus, 306/306 on borg -- ONE NONDETERMINISTIC TEST WHOSE FAILURE RATE IS HOST-DEPENDENT, not a clean passes/fails split, and borg's median native wall is 313.5s against seven's 184.3s. The test's OWN HEADER predicted this misreading -- it declares itself timing-independent (`NO sleep() ANYWHERE`, pipe handshakes) because `a flaky row in a cross-target matrix reads as a target bug` -- which is exactly what this ticket concluded twice, first as a code regression and then as a toolchain defect. The flake is also evidence the pipe discipline has a hole, since a test with no sleeps should not flake. THE LOAD READING IS THE BEST-SUPPORTED EXPLANATION AND IT IS frankuser's: restricted to the test's own lifetime (it was created 2026-09-04T16:54:32Z), seven separates PERFECTLY at ~215s wall -- 9 of 9 reports above it have the row red, 0 of 190 below it do -- and borg's median native wall is 313.5s, far above that, with plexus's HEAD tier at 417.3s flaking once in three attempts. That unifies the seven episode, borg's standing condition and the plexus flake without invoking gcc or qemu. IT IS A HYPOTHESIS AND NOT A RESULT: the nine reds are one contiguous 94-minute episode so wall and time stay confounded, and an absolute threshold does not transfer between machines. AN EARLIER SECTION CLAIMED THIS WAS REFUTED AND THAT CLAIM WAS BUILT ON A BUCKET WHERE A RED WAS IMPOSSIBLE -- the ten `clean` high-wall reports it rested on all PREDATE the test, so the row was absent rather than passing, and the post-birth 230s+ bucket is empty; heading withdrawn in place rather than deleted. KEEP THE TWO REGIMES APART, since merging them has misread this row three times: seven's nine reds are a BIRTH SHAKEDOWN, borg's 306/306 with flaky:0 always is a STANDING condition where all three attempts fail every time, and any explanation yielding `sometimes` does not explain borg. OUTSTANDING: `full` is untested on a non-borg host and stays open; the native green is ONE sample and wants repeats; and nothing here says borg reports falsely -- if the cause is a real race then borg is the honest instrument and the fast hosts hide it. EARLIER, AND STILL TRUE: the population is (TIER, HOST) and the first counts pooled it -- THE POPULATION IS (TIER, HOST) AND I POOLED IT: the last native GREEN is seven's LAST REPORT EVER, not a run that happened to be green -- the tiers did not stop going green, the host that was going green stopped REPORTING, and borg, which took over, has published no native GREEN since July. The 4h11m window contains three HOST-MIGRATION commits, so it is a handover rather than a bisect range. The always-red row splits by machine, not by time: c_crtl_wait is red in 9 of 638 seven reports (one 94-minute burst) and 306 of 467 borg reports, and IT PASSES AT HEAD ON THIS BOX -- measured, expectation recorded first, `testmgr --tier native --job test-core#src:test/c_crtl_wait.c` = GREEN on plexus. So it is not a code regression. seven and plexus run gcc 15.2.0 / qemu 10.2.1; borg runs gcc 13.3.0 / qemu 8.2.2, and the failure is a riscv32 waitid/si_code conversion under emulation -- qemu is the plausible member of three differing components and IS NOT PROVEN. The greedy percentages below stand as arithmetic and now describe how BORG's reds are distributed rather than how much compiler work exists. THE ONE MEASUREMENT THAT SETTLES IT: run a native tier on a non-borg host at HEAD; the two hosts overlap on exactly one day, so no amount of archive reading can attribute this. ALSO CORRECTED 2026-09-22 02:5x, and the first-published numbers (14/94 rows, 51%/37%) were LOW because they counted `## STILL-RED` and ignored `## NEW-RED` -- the union is what a report means by red, and a NEW-RED row is the most interesting kind to have dropped. Three discharges also landed there: the tier does NOT abort early (testmgr.py:591 names selfhost-fixedpoint as the only aborting job, and 0 of 306 and 0 of 313 reports are such an abort), so rows-per-report is a fact about the tier and not about the reporting; the native bisect window is 4h11m rather than eleven days; and the apparent green-count disagreement with frankuser was NEITHER parser -- 'newest 1500 commits' is a fixed-SIZE sliding window whose tail dropped exactly one opt and one slow green, reproduced exactly at the earlier tip. WHAT WOULD RETIRE THIS TICKET: a `full` report with verdict GREEN at any sha after 2026-09-09. WHAT WOULD RETIRE ITS NUMBERS: any re-run at a different pinned ref -- carry both rows rather than replacing, since a count whose ref was not recorded is unquotable rather than refuted."
---

# `native` and `full` are both never-green, and that is where the resemblance ends

## Population, stated, because a bare count is not re-derivable

- **Pinned ref `ad275f0d96c39784d92a3159b74f686159cc3390`** (2026-09-22 02:34).
  Every number below is against that sha, and the reports were read **from the
  pinned tree** (`git cat-file`), not from a working copy — this checkout was
  at `a9af520b2` at the time, five reports behind, so reading from disk would
  have been a different population.
- **2898 reports**, every `devdocs/progress/tstate/reports/*` at that sha, all
  tiers, all hosts. Parse asserts `docs == files` before counting anything.
- **Oracle:** each report's own YAML `tier`/`verdict` and its `## STILL-RED`
  section. No inference from commit subjects.

## The tier verdicts, and a second count carried rather than replaced

Newest 1500 commit subjects at the pin, tier taken from a **whitelist** of tier
names — `bench … RED (0 bench rows, 550 conf)` otherwise parses as a tier, and
`<tier> <sha> done` is a completion rather than a verdict:

| tier | GREEN | RED | frankuser, 01:40, unpinned |
| --- | --- | --- | --- |
| native | 0 | 166 | 0 / 165 |
| full | 0 | 103 | 0 / 102 |
| opt | 6 | 14 | 7 / 14 |
| slow | 27 | 2 | 28 / 2 |

Both counts agree on the only thing that matters and differ by ±1 per tier,
consistent with a window that moved between 01:40 and 02:34. **Neither refutes
the other; they measured different windows, and only one of them recorded its
ref.**

## "NEVER GREEN" IS A PROPERTY OF THE WINDOW, NOT OF THE TIER

Over all 2898 reports, `native` has **175** GREENs and `full` has **57**. They
are not tiers that cannot go green — they are tiers that **stopped**:

| tier | reports | GREEN | last GREEN |
| --- | --- | --- | --- |
| native | 1550 | 175 | 2026-09-11T16:28:30Z |
| full | 1188 | 57 | 2026-09-09T08:21:39Z |
| opt | 139 | 7 | 2026-09-16T17:43:25Z |
| slow | 17 | 5 | 2026-09-19T17:19:56Z |

That is worth more than the zero: it gives a **bounded bisect window** for each
tier instead of an open-ended one.

## THE ROWS — and this is the question an aggregate cannot answer

Counting distinct `## STILL-RED` rows in the RED reports **since each tier's own
last green**:

| | native | full |
| --- | --- | --- |
| RED reports in span | 306 | 313 |
| distinct rows ever red | **14** | **94** |
| rows per report (min/med/max) | 1 / **1** / 5 | 0 / **6** / 20 |
| rows red in ≥50% of reports | 1 | 4 |
| rows red in exactly one report | 1 | 34 |

**`test-core#src:test/c_crtl_wait.c` is red in 306 of 306 native reports.**

Greedy — clear the row that unblocks the most reports, then repeat:

    native                                        full
    1 row  -> 51% green                           1 row  ->  3% green
    2 rows -> 72%                                 4 rows -> 13%
    4 rows -> 79%                                 6 rows -> 20%
    8 rows -> 96%                                 8 rows -> 37%

**So they are different problems wearing one verdict.** `native` is a finishing
job — one test fixed makes half its runs green. `full` is a long tail where the
eight best rows leave 63% still red. Any plan, estimate or release claim that
treats "both tiers are never green" as one fact is wrong by roughly an order of
magnitude on one of the two, and which one depends on the direction you guessed.

## This is UN-FINISHED, not un-triaged

Every top row already has an open ticket — `c_crtl_wait` (4 open), `crtl_reachability`
(5), `test_threadsafe_heap_lock_deadlock_diag` (3), `crtl_atexit` (2),
`compiler_srchash` (6). **The gap is not filing and this ticket must not become
more of it.** What is missing is that nobody had the row count, so nobody could
see that native is one fix from half-green while full is not.

## Wiring

Feeds `umbrella-a-stranger-can-get-a-working-compiler-from-a-release` (p80),
whose `blocked-by` already names `umbrella-one-full-tier-run-with-no-red-tier` —
now in `done/`, closed 2026-09-07 **by a run rather than a decision**, with
`If it regresses, that is a new ticket` as its own last line. This is that
ticket. The closed umbrella is **not** reopened: it recorded a real event, and
a terminal ticket that stays true about the past is working correctly.

## Not established, and named so nobody assumes it

- **Whether the rows are the same FAILURE each time**, only that the same job id
  is red. A job id red for eleven days could be one cause or several.
- **Flakiness is not separated out.** Reports carry a `flaky` field that this
  census does not read; a row red in 1 of 313 reports may be noise rather than a
  defect, which is most of the 34 one-offs.
- **`opt` and `slow` are not characterised here** — they do go green and are not
  on the critical path for this claim.

## 2026-09-22 02:5x — FOUR CORRECTIONS TO THE SECTION ABOVE, THREE OF THEM MINE

frankuser reviewed the census and asked for three discharges. All three are
measured below, at the same pinned ref `ad275f0d96c3`.

### 1. MY ROW COUNTS WERE LOW: I COUNTED `## STILL-RED` AND IGNORED `## NEW-RED`

A report's red rows are the union of both sections and I parsed one. Corrected:

| | native | full |
| --- | --- | --- |
| distinct rows, STILL-RED only (as published) | 14 | 94 |
| **distinct rows, STILL-RED ∪ NEW-RED** | **33** | **129** |
| greedy, 1 row | 51% -> **42%** | 3% -> **1%** |
| greedy, 4 rows | 79% -> **73%** | 13% -> **11%** |
| greedy, 8 rows | 96% -> **90%** | 37% -> **32%** |

**The qualitative finding is unchanged and is if anything sharper** — native
still reaches 90% on eight rows where full reaches 32% — but **every specific
number in the section above is wrong by the NEW-RED rows** and the corrected
ones are these. A NEW-RED row is by definition the most interesting kind, so
omitting them was the worst available subset to drop.

### 2. THE TIER DOES NOT ABORT EARLY, SO `rows per report` IS A FACT ABOUT THE TIER

This was the load-bearing assumption: a first-failure report would make the
median of 1 a fact about the REPORTING, and the greedy estimate the
FPC-corpus illusion. Discharged by grep and by data. `tools/testmgr.py:591`
names exactly one aborting job — `SELFHOST_GATE_TARGET = "selfhost-fixedpoint"`,
*"the job whose red aborts the tier and publishes immediately"*. Everything else
runs to completion.

**And no report in either span is such an abort: 0 of 306 native and 0 of 313
full contain a selfhost or fixedpoint row.** The reports enumerate.

### 3. NEITHER PARSER DROPPED A GREEN — THE WINDOW IS FIXED-SIZE AND SLIDES

frankuser's counts (01:40, unpinned) and mine (02:34, pinned) differ by +1 red
on native and full and **-1 green on opt and slow**, and a green going DOWN
cannot be explained by a window that only grows. It is not one that only grows:
**"newest 1500 commits" has a fixed SIZE, so 12 commits entering at the head
push 12 out at the tail.**

Re-running my own parser at `882877364` — origin's tip at 01:43 — reproduces
frankuser's table **exactly**: `7 GREEN (opt), 28 GREEN (slow), 102 RED (full),
165 RED (native)`. And the 12 commits that fell off that tail contain
**precisely 1 GREEN (opt) and 1 GREEN (slow)**.

**Both counts were correct. The premise that needed correcting was "a
forward-moving window cannot remove a green"** — true of a window with a fixed
START, false of one with a fixed SIZE, and the ticket above filed the difference
under "a window that moved" without noticing it had to be a sliding one.

### 4. THE BISECT WINDOW IS FOUR HOURS, NOT ELEVEN DAYS

Last native GREEN `2026-09-11T16:28:30Z`; first native RED after it
`2026-09-11T20:39:22Z` — **4h11m** — and that first red report contains exactly
two rows: `test-core#src:test/c_crtl_wait.c` and
`test-core#src:test/cfnptr_array_callable.c`. Whatever ended the green era is in
those four hours of commits.

**BUT `c_crtl_wait` DOES NOT HAVE A CLEAN BREAK POINT AND THAT WEAKENS THE
ONE-ROW STORY.** Its first red report ever is `2026-09-04T17:24:43Z`, a week
BEFORE the last green — so it was red, then green, then red. It is not a row
that broke and stayed broken, and **"red in 306 of 306" is true only of the
window that starts after the last green.** Either it is environment-dependent or
it was fixed and re-broke; this census cannot tell those apart and does not
claim to. **Anyone bisecting should pin `cfnptr_array_callable.c` as the second
candidate rather than assuming the always-red row is the cause.**

For full, the first RED report after its last green has **no rows in either
section at all** (4 such reports in the span) — a RED verdict whose cause is
outside both lists, which this census does not explain.

### The one-run discharge, recorded BEFORE it is run

frankuser's proposal and it is the right instrument: **skip `c_crtl_wait` and
run ONE native tier.** Recorded expectation, so a null row is information:
with the corrected numbers, **42% of reports in the span had that row as their
ONLY blocker**, so a single run is closer to a coin toss than a confirmation —
it is worth running as a validity check on the greedy model, but **a red does
not refute the model and a green does not prove it.** The instrument that
actually settles the 42% is several runs, or skipping the top four rows at once
(73%).

## 2026-09-22 03:2x — THE TIER POPULATION IS (TIER, HOST) AND I POOLED IT. `native`'s ALWAYS-RED ROW PASSES AT HEAD ON THIS BOX.

Chasing frankuser's (a) — *how many commits is the 4h11m window* — produced 20
commits, and **three of them are host migrations**: `tstate(seven): retire seven
→ plexus`, `tstate(plexus): retire plexus → borg`, `tstate(borg): un-retire —
borg is a watcher host again`. **The window I called a bisect range is a host
handover.** Bisecting it would compare two machines.

### Every green in this ticket belongs to a host that stopped reporting

| tier | host | reports | GREEN | last GREEN | newest report |
| --- | --- | --- | --- | --- | --- |
| native | seven | 638 | 62 | **2026-09-11T16:28:30Z** | **2026-09-11T16:28:30Z** |
| native | borg | 467 | 49 | **2026-07-31** | 2026-09-22 |
| full | seven | 512 | 5 | **2026-09-09T08:21:39Z** | 2026-09-11 |
| full | borg | 426 | 34 | **2026-07-28** | 2026-09-22 |

**The last native GREEN is seven's LAST REPORT, not a run that happened to be
green.** The tiers did not stop going green — **the host that was going green
stopped reporting**, and borg, which took over, has not published a native GREEN
since July in either tier.

### The row that is red in 306 of 306 is red on ONE host

| host | native reports | `c_crtl_wait` red | window |
| --- | --- | --- | --- |
| seven | 638 | **9 (1%)** | one 94-minute burst on 2026-09-04 |
| borg | 467 | **306 (66%)** | continuously since borg's first post-un-retire report |

The red→green→red pattern that made this row look unbisectable was **an artefact
of pooling two hosts**. It is not speckled in time; it is split by machine.

### MEASURED, AT HEAD, ON THIS BOX — IT PASSES

    python3 tools/testmgr.py --tier native --job 'test-core#src:test/c_crtl_wait.c'
    PASS  test-core#2051  qemu  7.0s   1/1 pass   testmgr: GREEN

**Expectation was recorded before the run** (pass, because plexus matches
seven's toolchain). So the row is **not a code regression**: the tree at HEAD
passes it on a host that is not borg.

### The toolchains differ, and the failing subject points at one of the three

    seven   gcc=15.2.0  qemu=10.2.1  git=2.53.0      fp c8242c45e762
    plexus  gcc=15.2.0  qemu=10.2.1                  (this box, PASSES at HEAD)
    borg    gcc=13.3.0  qemu=8.2.2   git=2.43.0      fp 892e942692d7

The failure is `expect_same: MISMATCH [riscv32/c_wait26]`, and the test's own
fix commit (`68d26ecb5`) is *"riscv32 has no wait4 at all — waitid arm"*: on
riscv32 the implementation goes through `waitid` and converts `si_code`
(`CLD_STOPPED`/`CLD_CONTINUED`) into wait statuses, which the source comment
already names as *"exactly what such a conversion gets wrong"*.

**QEMU 8.2.2 versus 10.2.1 is the plausible member and it is NOT PROVEN.** The
toolchain differs in three components at once and this census isolated none of
them. What is established is narrower and still decisive for planning: **the row
fails on borg's toolchain and passes on seven's and plexus's, at HEAD.**

### What this does to the rest of the ticket

- **The greedy percentages stand as arithmetic and change meaning.** They
  describe how borg's reds are distributed, not how much compiler work exists.
  A row that passes everywhere else is not a fix anybody owes.
- **`full` is untouched by this and stays the harder problem** — 129 distinct
  rows, 32% at eight — but it inherits the same doubt: its reds are also all
  borg's now, and nobody has run a full tier on a qemu-10 box since 09-09.
- **The four rowless `full` REDs are all 2026-09-11 20:02–20:59** — inside the
  handover hour — and carry no infra marker. Not explained; now likelier to be
  migration artefacts than test failures.

### The measurement that would settle it, and nobody has it

**Run one native tier on a non-borg host at HEAD.** That separates "the tree is
red" from "borg's toolchain is red" in a single run, which no amount of archive
reading can do — the two hosts overlap on exactly **one day** (2026-09-11: borg
0 green/2, seven 3 green/4), so the archive cannot attribute this and neither
can I.

## 2026-09-22 03:5x — THE NATIVE TIER IS **GREEN AT HEAD** ON A NON-BORG HOST, 2580/2580. MY PREDICTION WAS WRONG AND THE UNION QUESTION IS ANSWERED.

    PXX_ALLOW_FULL_SUITE=1 tools/testmgr.py --tier native      # plexus, HEAD e5408b0e6
    == testmgr report (tier native, 417.3s wall) ==
      2580/2580 pass, 1 flaky (passed on retry)
    testmgr: GREEN

`compiler/pascal26` sha256 `06255ab1878c7061`. `frozen_tree_guard.sh check
nativetier` → *"tree frozen for the whole run — verdict is attributable"*, rc=0.
Quick was not enough because the question **is** the whole native row set; a
single job cannot produce a union.

### MY RECORDED PREDICTION WAS "PROBABLY RED" AND IT WAS WRONG

Written to a file before the run: *"the tier is probably RED, on rows drawn from
seven's own population"*, reasoning from seven's 10.6% green rate. **Wrong.**
Every row I named as a likely red passed:

| row | borg | seven | **plexus @ HEAD** |
| --- | --- | --- | --- |
| `c_crtl_wait.c` | 306/306 red | 9/638 red | **FLAKY — failed 1/3, passed 2/3** |
| `cfnptr_array_callable.c` | red | 0/387 red | **PASS** |
| `size_canary.py` | never red | 108 red | **PASS** |
| `test_libwriteln_parity.pas` | never red | 63 red | **PASS** |
| `test_exception_threads_race.pas` | never red | 61 red | **PASS** |
| `test_threadsafe_heap_lock_deadlock_diag.pas` | red | red | **PASS** |

**THE UNION IS SATISFIABLE AND IT IS SATISFIED.** The worry that borg's chronic
set and seven's chronic set were two disjoint populations needing separate
campaigns is **refuted**: both pass on one machine at HEAD, in one run. Clearing
borg's wall does not reveal seven's — seven's is already gone.

### AND THE FLAKY ROW IS THE ONE THIS TICKET WAS BUILT AROUND

    testmgr: test-core#2051 failed (rc=1) on attempt 1/3 — retrying (flake guard)
    FLAKY  test-core#2051  test/c_crtl_wait.c  (flaked, passed on attempt 2)

**So my "it PASSES at HEAD" was one draw from a nondeterministic test.** The
single-job run earlier tonight passed; in the tier the same row failed its first
attempt. **Without the flake guard's retry this tier would have been RED on
exactly borg's row.** Corrected reading across three hosts:

    seven    9 / 638   (1.4%)
    plexus   flaky — 1 fail in 3 attempts, one sitting
    borg   306 / 467   (100%, and its reports carry flaky: 0)

**That is not a host-PASSES/host-FAILS split. It is one nondeterministic test
whose failure rate is host-dependent**, from ~1% to 100%. The toolchain reading
in the section above is therefore **weaker than I left it**: a 100% rate on one
box is consistent with a timing- or scheduling-sensitive test on a slower box,
and **borg's median native wall is 313.5s against seven's 184.3s — 1.7x
slower.**

### THE TEST PREDICTED THIS MISREADING IN ITS OWN HEADER

`test/c_crtl_wait.c` states it was written to be timing-independent — *"NO
sleep() ANYWHERE. Every ordering this test needs is enforced with a pipe"* —
because *"a timing-based version of the WNOHANG rows passes on a fast box and
flakes on a loaded one, **and a flaky row in a cross-target matrix reads as a
target bug**."*

**That is precisely the misreading this ticket made**, twice: first as a code
regression, then as a toolchain defect. The author named the failure mode and it
happened anyway — and the flake is evidence the pipe discipline has a hole
somewhere, since a test with no sleeps should not flake at all.

### WHAT IS NOW ESTABLISHED, AND WHAT IS NOT

**Established.** The tree at HEAD passes the entire native set on a
gcc-15.2/qemu-10.2.1 host. The never-green record is **not** a statement about
the tree. `full` is untested here and remains open.

**NOT established, and this is one run.** A green tier is one sample, and the
one row that matters flaked inside it, so **a second and third run are needed
before "native is green at HEAD" is a property rather than an observation.**
Nothing here says borg is reporting falsely — borg's reds are TRUE ON BORG, and
if the cause is a real race then borg is the honest instrument and the fast
hosts are the ones hiding it.

**The `wait4`→`waitid` `si_code` conversion on riscv32 stays the lead** for
`c_crtl_wait`, and it is now a lead on a RACE rather than on a version skew.

### The schema change this justifies, with the instance attached

The `toolchain:` field first appears `2026-09-05T18:04:47Z` (measured, not
inferred). Reports before it have no such line, so *"this report has no
toolchain"* and *"this report predates the field"* are the same string — **and I
read the second as the first for ten minutes on plexus before checking.**
**Record in the report schema WHEN each field was introduced.** Also: there is
no job-count field at all, so `wall` is the only job-set proxy available; seven
carried `skips: 1` where borg carries `skips: 0`, so the two hosts did not even
run the same set.

## 2026-09-22 04:1x — [HEADING WITHDRAWN 04:3x: THE REFUTATION BELOW WAS BUILT ON A BUCKET IN WHICH A RED WAS IMPOSSIBLE. SEE THE NEXT SECTION -- THE LOAD HYPOTHESIS IS SUPPORTED, NOT REFUTED.] The row has never been modified since it was written

frankuser proposed that the real axis is **how long the box takes** — wall time
riding as a proxy for the toolchain difference — because the failure rate is
ordered like the wall (seven 184.3s / borg 313.5s). Two within-host tests, both
on seven so the toolchain is held fixed. **The first looked like a confirmation
and the distribution refutes it.**

### The medians agree with the hypothesis and the buckets destroy it

seven's 638 native reports, this row red versus not:

    row RED   n=  9   median wall 223.4s   (217.4 .. 229.5)
    row ok    n=629   median wall 153.2s   ( 67.3 .. 252.5)

A 1.46x elevated median, which is exactly what load predicts. **But the rate is
not monotone in wall — it is a BAND:**

    wall band     reports   row RED   rate
    0-120s            302        0      0%
    120-150s            6        0      0%
    150-180s          160        0      0%
    180-200s          145        0      0%
    200-215s            5        0      0%
    215-230s           10        9     90%
    230s+              10        0      0%

**Ten reports are SLOWER than every red and not one of them is red.** A load
gradient forbids that.

### And dating the band shows the reds are the FASTER half of one day

All twenty high-wall reports are 2026-09-04:

    13:51..16:28Z   ten reports, wall 246.3 .. 252.5s   ALL CLEAN
    17:00..18:34Z   nine reports, wall 217.4 .. 229.5s  ALL RED

**On one host, one day, one toolchain: the slower runs passed and the faster
runs failed.** So the elevated median was a DAY effect — every high-wall report
in seven's history is from 09-04 — and wall is not the axis. The hypothesis was
worth testing and it is dead.

### THE ROW HAS ONE COMMIT IN ITS ENTIRE HISTORY: ITS OWN CREATION

    git log --diff-filter=A -- test/c_crtl_wait.c
    68d26ecb5  2026-09-04 18:54:32 +0200 (16:54:32Z)
      fix(b): riscv32 has no wait4 at all — waitid arm, and the WIFSIGNALED cast it exposed

`git log -- test/c_crtl_wait.c` returns **that commit and nothing else.** So:

- the test was born at **16:54:32Z**;
- it went red at **17:00:09Z**, six minutes later;
- it was red for nine reports over 94 minutes;
- **it stopped failing at 18:34:32Z with NOTHING landing that touches it or the
  `waitid` path.** No commit between 18:34Z and the next clean report modifies
  the test, and the test has never been modified since.

**A test that stops failing without being changed was never fixed — that is the
proof of nondeterminism, and it is stronger than the flake guard's retry.** The
nine reds are the row's shakedown at birth, not a regression that was repaired.

### What that does to the per-attempt arithmetic

frankuser's amplification idea is right in form — a RED report means all three
attempts failed, so `p_attempt = p_report^(1/3)` — and **it is not usable for
seven, because the nine reds are ONE EPISODE rather than nine independent
trials.** Naively: seven `p_report` 0.014 → `p_attempt` 0.242; borg 1.000 →
1.000; plexus 1 failed attempt in 3. The seven figure is an episode masquerading
as a rate and must not be quoted. **Effective n for seven is 1.**

### Where this leaves the row, honestly

Unchanged since birth, nondeterministic, and its failure probability differs by
host for a reason that is **not** wall time and **not** established to be the
toolchain:

| host | reports | row red | note |
| --- | --- | --- | --- |
| seven | 638 | 9 — ONE 94-minute episode at the test's birth | qemu 10.2.1 |
| plexus | — | flaky: 1 failed attempt of 3, one sitting, at HEAD | qemu 10.2.1 |
| borg | 467 | **306, and 306/306 since un-retire** | qemu 8.2.2, `flaky: 0` always |

borg never records a flake recovery (`flaky: 0` in every sampled report), so on
borg the row appears to fail **all three attempts, every time** — which is a
different regime from "flakes occasionally", and the thing to explain.

**The lead is the race, not the version.** The test declares itself sleep-free
with pipe handshakes precisely so it cannot be timing-sensitive; it flakes
anyway, so the pipe discipline has a hole. That is a concrete bug with a
concrete owner (Track B / crtl, `waitid` si_code conversion on riscv32) and it
is not a tools ticket.

**And the goal-1 lesson, which is frankuser's sentence:** a green bought by
running on fast hardware is not a green. If a release is chased by moving to
quicker boxes, the race ships.

## 2026-09-22 04:3x — UN-RETRACTING THE LOAD HYPOTHESIS. MY REFUTATION HAD **ZERO** POST-BIRTH EVIDENCE, AND THE FILTERED DATA SEPARATES PERFECTLY.

frankuser caught it from the timeline in my own section above, and the arithmetic
is three characters wide: **the test was created at `2026-09-04T16:54:32Z`, and
the ten "ALL CLEAN" high-wall reports run `13:51..16:28Z`. 16:28 is before
16:54:32.** Every one of them **predates the test's existence**, so the row is
not in them. They are not clean — **the row is ABSENT**, and that bucket could
not have produced a red under any hypothesis whatsoever.

**So the instrument that refuted the load hypothesis was one in which the
refuting outcome was impossible.** Honest reports, correctly computed buckets,
real wall times, and a population that cannot contain the subject. This is the
same class as everything else tonight, in its purest form — and **the `git log`
line I wrote to explain the episode is what invalidates the analysis two
paragraphs above it.**

### Sized, then re-run with one filter: `date >= 2026-09-04T16:54:32Z`

    reports BEFORE the test existed (row ABSENT, not passing):  439
    reports AFTER  the test existed (row could fail):           199
    of the ten 230s+ "clean" reports, pre-birth:                 10 of 10

**The `230s+` bucket post-birth is EMPTY, n=0.** The refutation rested entirely
on pre-birth reports.

    row RED   n=  9   median 223.4s   (217.4 .. 229.5)
    row ok    n=190   median 169.6s   ( 71.2 .. 201.9)

    wall band     reports  row RED  rate
    0-120s             1        0     0%
    120-150s           2        0     0%
    150-180s         117        0     0%
    180-200s          69        0     0%
    200-215s           1        0     0%
    215-230s           9        9   100%
    230s+              0        0     -

**PERFECT SEPARATION AT ~215s: 9 of 9 above it are red, 0 of 190 below it are.**
And the ok-median moved 153.2s -> 169.6s exactly as frankuser predicted, because
the pre-birth reports were dragging it down. **Both numbers in my 1.46x were
computed over the wrong set.**

### So the load reading is the best-supported explanation, and it is frankuser's

| host | native wall | this row |
| --- | --- | --- |
| seven, below its threshold | < 215s | **0 of 190 red** |
| seven, above it | 215–230s | **9 of 9 red** |
| **borg** | **median 313.5s** | **306 of 306 red** |
| plexus, HEAD tier | 417.3s | **flaked — 1 failed attempt of 3** |

borg's every run sits far above the wall at which seven's row failed **100%** of
the time. That unifies the seven episode, borg's standing condition and tonight's
plexus flake without invoking gcc or qemu at all.

**Two limits that keep this a strong hypothesis rather than a result.** The nine
reds are still ONE CONTIGUOUS 94-MINUTE EPISODE, so within the post-birth set
wall and time remain confounded and the effective n is small. And **an absolute
wall threshold does not transfer between machines** — 215s on seven is not 215s
on plexus, since wall measures the box as much as the load; plexus ran 417.3s
and only flaked. What transfers is the *within-host* ordering, not the number.

### What was never affected by any of this

The row has **one commit in its history, its own creation**; it went red six
minutes after birth; it was red for nine reports over 94 minutes; **it stopped
failing with nothing landing that touches it or the `waitid` path, and has never
been modified since.** *A test that stops failing without being changed was never
fixed.* Independent of every wall-time question.

**And keep the two regimes apart** — merging them is how this row has been
misread three times now. seven's nine reds are a **birth shakedown**; borg's
306/306 with `flaky: 0` in every sampled report is a **standing condition in
which all three attempts fail every time.** Any explanation that yields
"sometimes" does not explain borg. The Track B / crtl routing for the `waitid`
`si_code` conversion on riscv32 is unchanged by all of it.
