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
summary: '`native` and `full` are both never-green and the resemblance ends there -- which no aggregate verdict can say and which decides how much work `full green expected` actually is. MEASURED at pinned ref `ad275f0d96c3` over all 2898 tstate reports: NATIVE IS A FINISHING JOB (33 distinct rows ever red across 306 RED reports; clearing one row makes 42% of them green, four rows 73%, eight rows 90%) and FULL IS BROAD (129 distinct rows over 313 RED reports, median 6 per report, best eight reach only 32% -- a long tail, not a few chronic blockers). Quoting one tier''s difficulty for the other is the error this ticket exists to prevent. Every top row already has an open ticket, so this state is UN-FINISHED rather than un-triaged and the fix is not more filing. SETTLED 2026-09-22 FOR `native`, AND THE MECHANISM IS AN EMULATOR VERSION RATHER THAN ANYTHING IN OUR CODE: a cross-target row can be red on one host and green on another FROM BYTE-IDENTICAL COMPILER BYTES, because a tstate verdict is a statement about a qemu as much as about a tree. Censused over every native/full report since the subject test''s only commit (population, tree and skips printed in the body): qemu 8.2.2 -> 541 RED / 4 ok (99.3%), qemu 10.2.1 -> 0 RED / 361 ok, plus 0 DIFF in 600 per-attempt draws on a 10.2.1 box. borg runs 8.2.2 and IS Track T''s breadth instrument, so a whole class of its reds has been arriving as code reds. A FULL NATIVE TIER AT HEAD IS GREEN ON A NON-BORG HOST (2580/2580, plexus, tree e5408b0e6, compiler 06255ab1878c, frozen-tree guard green, 417.3s), so the never-green record is not a statement about the tree, and the fear that borg''s chronic rows and seven''s were two disjoint populations needing separate campaigns is REFUTED. THE CONDITION THAT WOULD SPRING THIS AGAIN, stated as a mechanism because a named row decays: any verdict compared across a host whose toolchain moved, since WALL TIME AND EMULATOR VERSION ARE COLLINEAR ACROSS AN UPGRADE -- one host''s upgrade took its tier wall from ~227s to ~151s AND its red to green in the same instant, which separated 9 reds from 190 greens at ~215s wall with no exceptions and reads as a load-induced race. PERFECT SEPARATION IS THE SIGNATURE OF A CONFOUND, NOT OF A GRADIENT (frankuser, predicted before the data). An earlier load reading in this ticket is REFUTED on that ground and its heading is withdrawn in place; an earlier refutation OF that reading was itself withdrawn for resting on a bucket where a red was impossible. THE `toolchain:` FIELD EXISTS BECAUSE OF THIS ROW -- so its ABSENCE from the nine oldest reds is not missing data, it dates the upgrade, and the general form is worth more than this ticket: when a comparison''s `before` side is empty because a field did not exist yet, find out WHY THE FIELD WAS ADDED, because an observability field is a dated record of a past investigation and it is probably the same one. SEPARATE AND REAL FINDING, not merged with the above: deliberate load DOES induce failures -- 1-2% per attempt across ALL FIVE target arms at load ~24 against 0 of 600 at ambient ~5 -- which fires the falsifier registered before the data (if it moves every arm it is not the one target''s conversion) and is the better explanation for the single flake inside the plexus green. Its consequence is GOAL-1 arithmetic: with three attempts a per-attempt rate p gives 1-(1-p^3)^2580 for a 2580-job tier, ~2% at p=0.02 but ~92% at p=0.10, so RUNNING A RELEASE-GRADE TIER ON AN IDLE BOX IS ARITHMETIC RATHER THAN FASTIDIOUSNESS and belongs in the release criteria; treat the table as an upper bound since it assumes the rate is generic. ONE OWNER ACTION, stated in goal terms and needing no design fork: our breadth instrument reports failures that are not in our code, and upgrading one host''s emulator removes a whole class -- that needs sudo on borg, which is authority only he holds. Nothing else here waits on him. OUTSTANDING: `full` is still untested on a non-borg host and stays open; the native green is ONE sample and wants repeats; the four borg `full` reports of 2026-09-11 20:02-20:59 that pass under 8.2.2 are the 0.7% and are unexplained. WHAT WOULD RETIRE THIS TICKET: a `full` report with verdict GREEN at any sha after 2026-09-09. WHAT WOULD RETIRE ITS NUMBERS: any re-run at a different pinned ref -- carry both rows rather than replacing, since a count whose ref was not recorded is unquotable rather than refuted.'
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

## SETTLED 2026-09-22: THE ROW IS A qemu VERSION DIFFERENCE, NOT A RACE — AND THE TREE HAD SAID SO SINCE 2026-09-04

**The load reading in the section above is REFUTED, and this time by the right
instrument rather than by a bucket where a red was impossible.** frankuser
predicted the refutation before seeing any data, from the shape of my own
numbers: *"9 of 9 above and 0 of 190 below is TOO CLEAN for the mechanism I
proposed. Perfect separation is the signature of a confound, not of a
gradient."* It was a confound. The confounder is the **emulator version**.

### What borg actually fails on — one line, and not the line the header predicts

```
expect_same: MISMATCH [riscv32/c_wait26]
-wait4-rusage     rusage=written
+wait4-rusage     rusage=UNTOUCHED
```

Deterministic, riscv32 only, and it is the **rusage** row — *not* the
stopped/continued `si_code` reconstruction that the test's own header nominates
as the fragile part, and not anything a pipe handshake could race on. Every
earlier reading of this ticket, mine included, guessed the header's row.

### The census, with its population printed

`devdocs/progress/tstate/reports/*.md` at tree `cb22d13034fb`, restricted to
`tier in {native, full}` (the only tiers that run `test-core`) and to
`date >= 2026-09-04T16:54:32Z` — the test's one and only commit, `68d26ecb5`.
2903 files; 161 skipped as another tier, 1822 as pre-birth, 14 with no
`toolchain:` field. A report lists only its reds, so for a report that ran the
row, absence is a pass; that is the one soft step and it is stated, not hidden.

| qemu | gcc | RED | ok | red % |
| --- | --- | --- | --- | --- |
| 10.2.1 | 15.2.0 | **0** | 361 | 0.0% |
| 8.2.2 | 13.3.0 | **541** | 4 | 99.3% |

| host | qemu | RED | ok | red % | first red |
| --- | --- | --- | --- | --- | --- |
| borg | 8.2.2 | 541 | 4 | 99.3% | 2026-09-11T19:51:21Z |
| seven | 10.2.1 | 0 | 361 | 0.0% | — |

Plus, from this box: **plexus, qemu 10.2.1, 0 DIFF in 600 per-attempt draws.**

### The 215s "threshold" was the wall-time SHADOW of an upgrade

seven's native reports, post-birth, in date order — the table that dissolves it:

| date | row | wall | `toolchain:` |
| --- | --- | --- | --- |
| 2026-09-04T17:00:09Z | RED | 217.4 | ABSENT |
| … 7 more consecutive REDs … | RED | 218.3–227.0 | ABSENT |
| 2026-09-04T18:34:32Z | RED | 227.0 | ABSENT |
| *— 23-hour gap —* | | | |
| 2026-09-05T17:58:11Z | **ok** | **153.2** | ABSENT |
| 2026-09-05T18:04:47Z | ok | 151.3 | `gcc=15.2.0 qemu=10.2.1` |
| … 188 more, to 2026-09-11T16:28:30Z … | ok | 151–202 | `qemu=10.2.1` |

**The row went green and the tier wall fell 33% at the same instant**, in a gap
with nothing landing in the repo. qemu 8.2.2 was slower AND red; 10.2.1 is
faster AND green. So on that host **wall time and emulator version are
perfectly collinear**, and every number in the superseded section above was
measuring the upgrade. A step at a software boundary, not a gradient — which is
exactly why it separated without a single exception.

**My earlier note contained the tell and drew the opposite conclusion from it:**
*"it stopped failing at 18:34:32Z with nothing landing — a test that stops
failing without being changed was never fixed."* The instinct was right. What I
did not consider is that **the change can be in the MACHINE rather than in the
tree**, and the archive could not tell me because the field that would have
said so did not exist yet.

### AND THE ANSWER WAS ALREADY WRITTEN DOWN, BY THE FIELD'S OWN AUTHOR

`tools/twatch.py`, in the comment that introduces `toolchain:`, dated
2026-09-04 — before the nine reds had finished:

> *"`c_crtl_wait.c`'s riscv32 rusage row was red on one and green on the other
> from BYTE-IDENTICAL compiler bytes, and no field in the archive could tell a
> reader that."*

**The `toolchain:` field exists BECAUSE of this row.** Its absence from the
nine reds is not missing data — it is the timestamp of the upgrade, because the
field was added in response to this failure. frankuser had asked, the night
before, for the schema to record when each field was introduced; the answer
here is that the field was introduced *by this ticket's own row*, and one
lookup would have replaced the whole wall-time investigation.

**One correction to that comment, landed with this:** it names **seven** as the
8.2.2 box and plexus as 10.2.1. True when written, stale within a day — seven
was upgraded on 2026-09-05 and **borg** is the 8.2.2 box now. A worked example
decaying in the direction that sends the next reader to the wrong host.

### The load arms, kept and labelled for what they can prove

Per-attempt instrument (the recipe's own comparison, one gcc oracle,
`expect_same` per arm, one attempt per invocation — the tier reports a 3-attempt
aggregate and so cannot give a per-attempt rate). Two positive controls, both
firing: a mutated oracle makes all five arms DIFF; a deliberately wrong riscv32
binary makes riscv32 alone DIFF.

| condition | load1 | native | i386 | arm32 | aarch64 | riscv32 |
| --- | --- | --- | --- | --- | --- | --- |
| ambient, n=120 | 4.7–5.7 | 0% | 0% | 0% | 0% | 0% |
| 24 burners nice 19, n=100 | 20.2–26.8 | 2% | 1% | 1% | 0% | 2% |

**Load does induce real failures — and it moves all five arms about equally,
which fires the falsifier registered before the data: if it moves all five it
is not the riscv32 `waitid` conversion.** So generic load-induced flakiness is a
SEPARATE and real finding, and it is the better explanation for the single flake
inside the 2580/2580 plexus green. **The two are not merged.**

Scope limit, frankuser's and 8e's jointly and it is a fair one: `nice 19` is
specifically the load that does not take CPU from a nice-0 subject, so a NULL
from this arm would have proved nothing. It was not null, which is the only
reason the row is quotable. Anyone needing the real dose-response curve should
throttle the subject (`CPUQuota`) rather than load the box.

### What this changes about the ticket

- `native`'s chronic row is **not compiler work and not a race**. It is one
  target's `rusage` result under an emulator four minor versions old.
- **Routing stays Track B / crtl** — the `wait4`/`waitid` rusage path on
  riscv32 — but the priority drops: no correct Pascal or C program is
  mis-compiled, and the green tier at HEAD on 10.2.1 is not bought by fast
  hardware, which was the worry.
- The greedy percentages earlier in this ticket describe **how borg's reds are
  distributed under qemu 8.2.2**, which is a statement about one host's
  emulator, not about how much work `full green expected` is.
- **`full` is still untested off borg** and that stays open.

### What would retire THIS section

A report with `qemu=8.2.2` where the row is **ok**, at any sha, other than the
four borg `full` reports of 2026-09-11 20:02–20:59 already counted above — those
four are the 0.7% and are unexplained. Or a `qemu=10.2.1` report where it is
RED. Either would mean the emulator version is not the variable.

## THE GOAL-1 CONSEQUENCE: TIER GREENNESS IS A STEEP FUNCTION OF MACHINE LOAD

frankuser's arithmetic off the load arms, and it is the deliverable from the
arm that nearly did not run. With three attempts, a per-attempt failure rate
`p` gives a per-job red of `p^3`, and over 2580 jobs the chance of at least one
red is `1 - (1 - p^3)^2580`:

| per-attempt `p` | chance a 2580-job tier has >= 1 red |
| --- | --- |
| 0.02 (measured at load ~24) | ~2% |
| 0.05 | ~28% |
| 0.10 | ~92% |

**STATED AS AN UPPER BOUND, NOT AN ESTIMATE, AND THE CAVEAT IS FRANKUSER'S
OWN:** this assumes the measured rate is generic across jobs. Most jobs are
surely deterministic and immune, so the real figure is lower — the table's
value is the SHAPE, not the numbers. What the shape says is that the retry's
cube is doing enormous work, and that tier greenness falls off a cliff as load
rises.

**SO "RUN THE RELEASE-GRADE TIER ON AN IDLE BOX" IS ARITHMETIC, NOT
FASTIDIOUSNESS, AND IT BELONGS IN THE RELEASE CRITERIA AS A STATED
REQUIREMENT.** Goal 1 is *"making a full green pin as release"*, and the pin
rule since 2026-09-07 is *"full green expected"*. If a release-grade tier is run
on a contended box, a red is the expected outcome rather than a finding, and
whoever sees it first goes looking for a compiler bug — which is exactly the
several hours this ticket has now consumed twice. **Record the achieved load
beside a tier verdict, the way a population line goes beside a count.**

## RECOMMENDATION FOR THE OWNER — one number, one action, no design fork

**Stated in goal terms because that is the form that is answerable:** *our
breadth instrument is reporting failures that are not in our code, and
upgrading one host's emulator removes a whole class of them.*

- borg runs **qemu 8.2.2**; seven and plexus run **10.2.1**.
- On 8.2.2 this class is **541 RED / 4 ok**. On 10.2.1 it is **0 RED / 361 ok**.
- borg is Track T's breadth instrument — the machine whose reds every lane is
  told to trust — so every one of those 541 reds has been arriving as a code
  red, and this ticket is the second investigation to have chased one.

**Why it is an escalation and not ours to do:** upgrading a package on borg
needs sudo on that host, which is authority only the owner holds. It is not a
fork of intent and it is not a cost trade-off; it is one action. Nothing else
in this ticket is waiting on him.

**What it does NOT claim:** that borg reports falsely. borg is honest about
qemu 8.2.2. The question is whether we want our breadth instrument to be a
statement about a 2024 emulator, and only he can action the answer.

## THE REUSABLE FINDING, and it is frankuser's phrasing

> **When a comparison's "before" side is empty because a field did not exist
> yet, go and find out WHY the field was added. An observability field is a
> dated record of a past investigation — and if you are looking at that field,
> it is probably the same investigation.**

Both of us read the nine reds' missing `toolchain:` as **damage to the
population**. It was the opposite: the field's absence dated the upgrade, and
the commit that added the field named this row as its reason. The schema
question (*when was each field introduced?*) and the causal question (*why did
this row stop failing?*) were **the same question**, and the one I treated as
hygiene was the one that held the answer.

## THE CONTROL THAT STOPS THIS BEING "borg IS RED AT EVERYTHING" — AND THE ONE ROW THAT RUNS BACKWARDS

**The problem with everything above, stated before anyone else has to:** in this
window **host and toolchain are 1:1** — borg is the only 8.2.2 box and seven the
only 10.2.1 one — so a split on toolchain and a split on *host* are the SAME
split, and nothing in the cross-tab can tell them apart. That is this repo's own
"correct instrument, wrong population" arriving in my own table, and a 99.3%
versus 0.0% row is exactly the kind of number nobody interrogates.

**Two things break the tie, and only the second is a measurement of mine.**

**1. The within-host flip.** seven itself was on the OLD toolchain before
2026-09-05 and red, and on the new one after and green — same machine, same
sweeper, toolchain changed underneath. That is a within-host control and it is
the strongest single fact here. **Its one inferential link, named rather than
buried:** the nine pre-upgrade reds carry no `toolchain:` field, so that they
ran 8.2.2 comes from `twatch.py`'s own dated statement of 2026-09-04 rather
than from the reports. That is a recorded measurement by the field's author,
not an assumption — but it is testimony, not data, and it is the one place this
argument leans on something outside the archive.

**2. Other chronic rows do NOT separate this way** — same instrument, same
population, same two toolchains, `tools/tstate_row_by_toolchain.py`:

| row | qemu 10.2.1 | qemu 8.2.2 |
| --- | --- | --- |
| `c_crtl_wait` | **0.0%** (0/361) | **99.3%** (541/545) |
| `crtl_reachability` | 27.1% | 42.8% |
| `threadsafe_heap_lock_deadlock_diag` | 1.1% | 42.2% |
| `crtl_atexit` | 0.0% | 12.8% |
| `compiler_srchash` | **34.9%** | **7.2%** |

**`compiler_srchash` is MORE red on the NEWER toolchain, and that reversal is
the control doing its job.** If the cross-tab were simply reporting "borg reds a
lot", every row would lean the same way and the instrument would be unfalsifiable
— a guard that cannot fail. One row leaning the other way, and three leaning
weakly, means the table has discriminating power and that `c_crtl_wait`'s
99.3%/0.0% is genuinely exceptional rather than an artefact of which box was
sweeping.

**What this control does NOT establish:** that the emulator is the *mechanism*
rather than the gcc or the kernel, all three of which moved together. The
failing observable is a `rusage` struct left untouched by a `waitid`-based path
under user-mode emulation, which makes qemu the plausible member — and that is
an argument, not a measurement. **Naming it: PLAUSIBLE, NOT PROVEN.** What would
prove it is one run of this row under qemu 8.2.2 and 10.2.1 *on the same host
with the same gcc*, which needs a second emulator installed and is a cheap job
for whoever has that box.
