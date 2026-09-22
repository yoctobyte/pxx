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
summary: '`native` and `full` are both never-green and the resemblance ends there -- which no aggregate verdict can say and which decides how much work `full green expected` actually is. MEASURED at pinned ref `ad275f0d96c3` over all 2898 tstate reports: NATIVE IS A FINISHING JOB (33 distinct rows ever red across 306 RED reports; clearing one row makes 42% of them green, four rows 73%, eight rows 90%) and FULL IS BROAD (129 distinct rows over 313 RED reports, median 6 per report, best eight reach only 32% -- a long tail, not a few chronic blockers). Quoting one tier''s difficulty for the other is the error this ticket exists to prevent. Every top row already has an open ticket, so this state is UN-FINISHED rather than un-triaged and the fix is not more filing. SETTLED 2026-09-22 FOR `native`, AND THE MECHANISM IS AN EMULATOR VERSION RATHER THAN ANYTHING IN OUR CODE: a cross-target row can be red on one host and green on another FROM BYTE-IDENTICAL COMPILER BYTES, because a tstate verdict is a statement about a qemu as much as about a tree. Censused over every native/full report since the subject test''s only commit (population, tree and skips printed in the body): qemu 8.2.2 -> 546 RED / 1 ok (99.8%), qemu 10.2.1 -> 0 RED / 361 ok, plus 0 DIFF in 600 per-attempt draws on a 10.2.1 box. borg runs 8.2.2 and IS Track T''s breadth instrument, so a whole class of its reds has been arriving as code reds. A FULL NATIVE TIER AT HEAD IS GREEN ON A NON-BORG HOST (2580/2580, plexus, tree e5408b0e6, compiler 06255ab1878c, frozen-tree guard green, 417.3s), so the never-green record is not a statement about the tree, and the fear that borg''s chronic rows and seven''s were two disjoint populations needing separate campaigns is REFUTED. THE CONDITION THAT WOULD SPRING THIS AGAIN, stated as a mechanism because a named row decays: any verdict compared across a host whose toolchain moved, since WALL TIME AND EMULATOR VERSION ARE COLLINEAR ACROSS AN UPGRADE -- one host''s upgrade took its tier wall from ~227s to ~151s AND its red to green in the same instant, which separated 9 reds from 190 greens at ~215s wall with no exceptions and reads as a load-induced race. PERFECT SEPARATION IS THE SIGNATURE OF A CONFOUND, NOT OF A GRADIENT (frankuser, predicted before the data). An earlier load reading in this ticket is REFUTED on that ground and its heading is withdrawn in place; an earlier refutation OF that reading was itself withdrawn for resting on a bucket where a red was impossible. THE `toolchain:` FIELD EXISTS BECAUSE OF THIS ROW -- so its ABSENCE from the nine oldest reds is not missing data, it dates the upgrade, and the general form is worth more than this ticket: when a comparison''s `before` side is empty because a field did not exist yet, find out WHY THE FIELD WAS ADDED, because an observability field is a dated record of a past investigation and it is probably the same one. SEPARATE AND REAL FINDING, not merged with the above: deliberate load DOES induce failures -- 1-2% per attempt across ALL FIVE target arms at load ~24 against 0 of 600 at ambient ~5 -- which fires the falsifier registered before the data (if it moves every arm it is not the one target''s conversion) and is the better explanation for the single flake inside the plexus green. Its consequence is GOAL-1 arithmetic: with three attempts a per-attempt rate p gives 1-(1-p^3)^2580 for a 2580-job tier, ~2% at p=0.02 but ~92% at p=0.10, so RUNNING A RELEASE-GRADE TIER ON AN IDLE BOX IS ARITHMETIC RATHER THAN FASTIDIOUSNESS and belongs in the release criteria; treat the table as an upper bound since it assumes the rate is generic. ONE OWNER ACTION, and it is a TRADE rather than a free win -- stating it one-way was my error and frankuser caught it: upgrading borg''s qemu removes a class that is red in 546 of 547 reports, AND IT IS A TRADE, BUT NOT THE ONE FIRST PUBLISHED: my `compiler_srchash` control and its pre-registration are WITHDRAWN IN PLACE -- that name is NOT A ROW, it is a shared SOURCE PREREQUISITE matched by SUBSTRING across 28+ distinct job ids failing for unrelated reasons, which is the fifth population error in this ticket and the first to reach a pre-registration another seat was about to hand the owner. The structural tell is checkable in one lookup and is now the rule: A SHARED PREREQUISITE IS NOT A SUBJECT, so ask a name''s CARDINALITY before treating it as a row -- and when a row''s failure detail names something else (here `00184.c` in a C-conformance shard), the row is not a row. `tools/tstate_row_by_toolchain.py` now prints the job ids its pattern matched and ABORTS on more than one unless --aggregate is passed. THE MAIN FINDING IS UNAFFECTED and was checked first: `c_crtl_wait` is EXACTLY ONE job id (`test-core#src:test/c_crtl_wait.c`), as are the other three controls. RE-DERIVED over full job ids with `tools/tstate_toolchain_reversals.py`, the control is STRONGER than the one withdrawn: FIFTEEN genuine job ids are materially more red on the NEWER emulator (size_canary 189/361 52.4% vs 48/550 8.7%; install_lib_candidates 107/361 29.6% vs 0/550; test_libwriteln_parity 86/361 23.8% vs 0/550; test_emit_obj@3 65/361 18.0% vs 0/550; three lib_synapse rows 41/361 11.4% vs 0/550), against c_crtl_wait at 0/361 versus 549/550 -- so the cross-tab discriminates in BOTH directions on real rows, which is what the unfalsifiability objection asked for. BUT SEVERAL REVERSED ROWS ARE HOST-SIDE (`size_canary.py`, `install_lib_candidates.sh` execute nothing under emulation) and host/toolchain are 1:1 all window, so the REVERSED direction carries the same confound as the forward one and those rates may be about SEVEN rather than about 10.2.1. FREE CONTROL, frankuser''s: tonight''s plexus 2580/2580 GREEN is itself a 10.2.1 sample, and the four reversed rows that are native jobs ALL PASSED there -- suggestive, NOT a result, since P(all four pass) is ~30% if the rates transferred and size_canary at 52.4% passing is a coin flip. The `full` tier on plexus settles it and covers the seven full-only rows; prediction recorded first: most of the fifteen should pass. AND THE HONEST SIZE OF THE PRIZE, frankuser''s correction: the upgrade does NOT deliver a green tier -- a tier needing the top five green is green about one run in five -- it converts `never green, verdict carries no information` into `sometimes green, and a red means something`. THE DELIVERABLE IS INFORMATION, NOT GREEN, and those fifteen rows are the real goal-1 backlog, not the emulator. Recommendation unchanged and the asymmetry carries it: one row at 99.8% reds every verdict before anything else is consulted, the worst incoming row is 52.4% and the rest intermittent and IN OUR OWN TREE where we can fix them. Needs sudo on borg, which is authority only he holds. Nothing else here waits on him. OUTSTANDING: `full` is still untested on a non-borg host and stays open; the native green is ONE sample and wants repeats; the four borg reports once thought to pass under 8.2.2 were a PARSER BUG of mine (a third red-section spelling, `## RED`, 4 occurrences archive-wide); corrected to 546/1, and the ONE surviving exception is report 20260911T200220Z-1d8db86-borg, whose tier did reach the row. WHAT WOULD RETIRE THIS TICKET: a `full` report with verdict GREEN at any sha after 2026-09-09. WHAT WOULD RETIRE ITS NUMBERS: any re-run at a different pinned ref -- carry both rows rather than replacing, since a count whose ref was not recorded is unquotable rather than refuted.'
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
| 8.2.2 | 13.3.0 | **546** | 1 | 99.8% |

| host | qemu | RED | ok | red % | first red |
| --- | --- | --- | --- | --- | --- |
| borg | 8.2.2 | 546 | 1 | 99.8% | 2026-09-11T19:51:21Z |
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
- On 8.2.2 this class is **546 RED / 1 ok**. On 10.2.1 it is **0 RED / 361 ok**.
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
"correct instrument, wrong population" arriving in my own table, and a 99.8%
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
| `c_crtl_wait` | **0.0%** (0/361) | **99.8%** (546/547) |
| `crtl_reachability` | 27.1% | 43.3% |
| `threadsafe_heap_lock_deadlock_diag` | 1.1% | 42.0% |
| `crtl_atexit` | 0.0% | 12.8% |
| `compiler_srchash` | **34.9%** | **7.9%** |

**`compiler_srchash` is MORE red on the NEWER toolchain, and that reversal is
the control doing its job.** If the cross-tab were simply reporting "borg reds a
lot", every row would lean the same way and the instrument would be unfalsifiable
— a guard that cannot fail. One row leaning the other way, and three leaning
weakly, means the table has discriminating power and that `c_crtl_wait`'s
99.8%/0.0% is genuinely exceptional rather than an artefact of which box was
sweeping.

**What this control does NOT establish:** that the emulator is the *mechanism*
rather than the gcc or the kernel, all three of which moved together. The
failing observable is a `rusage` struct left untouched by a `waitid`-based path
under user-mode emulation, which makes qemu the plausible member — and that is
an argument, not a measurement. **Naming it: PLAUSIBLE, NOT PROVEN.** What would
prove it is one run of this row under qemu 8.2.2 and 10.2.1 *on the same host
with the same gcc*, which needs a second emulator installed and is a cheap job
for whoever has that box.

## CORRECTION, SAME NIGHT: THE FOUR "PASSES" UNDER 8.2.2 WERE A PARSER BUG OF MINE, AND IT IS THE THIRD INSTANCE OF ONE MISTAKE

**Published an hour earlier: `8.2.2 -> 541 RED / 4 ok (99.3%)`. Corrected:
`546 RED / 1 ok (99.8%)`.** The 10.2.1 column is unchanged at `0 RED / 361 ok`.
Both rows are carried rather than one replacing the other, per this repo's own
rule, and the reason the first was wrong is more useful than the delta.

**The bug.** My matcher counted a row as red if it appeared under `## STILL-RED`
or `## NEW-RED`. Four reports head their red list `## RED — no baseline at this
sha, so none of these is classified as new or inherited`, and that spelling
exists in **exactly four files archive-wide** — the same four I had scored as
passes and then written up in the ticket as "the 0.7% and unexplained". They
were never unexplained. They were mine.

**AND THIS IS THE THIRD TIME THE SAME MISTAKE HAS BEEN MADE ON THIS ARCHIVE,
ALWAYS BY GUESSING THE SPELLINGS INSTEAD OF ENUMERATING THEM.** First,
counting `STILL-RED` and dropping `NEW-RED` — which moved native's distinct rows
from 14 to 33 and full's from 94 to 129. Then this. The whole vocabulary is one
command:

```
$ grep -h '^## ' devdocs/progress/tstate/reports/*.md | sed 's/ —.*//' | sort | uniq -c
   2473 ## STILL-RED
   1455 ## first failure
   1247 ## failure detail
    605 ## NEW-RED
    581 ## FIXED
      4 ## RED
```

**Four occurrences out of 6365 headings, and they were the whole anomaly.** A
long-tail spelling is exactly what a guessed matcher misses and exactly what a
census cannot notice, because the miss presents as *data* — four clean passes
that invite a story. I wrote the story.

**THE FIX IS AN ASSERTION, NOT A LONGER GUESS.** `tools/tstate_row_by_toolchain.py`
now holds a CLOSED vocabulary and **aborts on any heading it does not
classify**, naming the file and the heading. A new section spelling can no
longer be silently scored as a pass; it stops the run. The distinction matters
because the two error directions are not symmetric here: a crash costs a minute,
a silent miscount got published and argued from.

**What the correction changes downstream:** nothing in the mechanism, and the
control table only in the third digit — `crtl_reachability` 27.1%/43.3%,
`threadsafe_heap_lock_deadlock_diag` 1.1%/42.0%, `crtl_atexit` 0.0%/12.8%,
`compiler_srchash` 34.9%/7.9%. **`compiler_srchash` still runs backwards**, so
the control still discriminates and that argument is untouched.

**THE ONE SURVIVING EXCEPTION, and it is now a real one.** Report
`20260911T200220Z-1d8db86-borg`, `full`, wall 597.4s, `skips: 0`, verdict RED:
its red list holds **4 rows and the row is not among them**, and it names
`test-core` three times, so the tier did reach that job. So the row genuinely
passed once under 8.2.2 in 547 reports. Its red list is unusually short and its
wall unusually low for a borg `full`, which is worth noting and is not an
explanation. **What would settle it:** re-running that sha on an 8.2.2 host.

**Population note, because it moved under me:** this correction reads 2905
reports at tree `1ef9c9bcb` where the first pass read 2903 at `cb22d13034fb` —
two reports arrived in my own `sync.sh` pull between the two runs. That is the
push-is-a-pull hazard, and it is why both rows carry their tree.

## MY RECOMMENDATION ON THE UPGRADE, BECAUSE THE NUMBERS ALONE ARE A ONE-WAY CASE AND IT IS NOT ONE

frankuser caught that my "upgrading one host's emulator removes a whole class"
is not free, and it was right to: `compiler_srchash` runs the other way, **7.9%
red on 8.2.2 against 34.9% on 10.2.1**. So the honest trade is *remove a
deterministic class, and plausibly quintuple a flaky row we would then own.*
Asked which I would do:

**UPGRADE IT. The decisive fact is not the ratio, it is that there is only ONE
sweeping host left.** seven's last report is 2026-09-11T16:28:30Z; borg took
over and every native/full verdict since is borg's. So the state of the world
is:

- **Today: `c_crtl_wait` is red in 546 of 547 borg reports.** A row that fails
  ~100% of the time makes *every* native and full verdict RED before any other
  row is consulted. The tier's verdict carries **no information** — which is
  this ticket's own opening observation, arrived at from the other end.
- **After: that row goes to 0%, and `compiler_srchash` plausibly goes to ~35%.**
  A 35% row is bad and it is not 100%. Tier greenness goes from
  *impossible-in-principle* to *roughly two runs in three on that row*.

**AND THE SECOND REASON IS THE ONE I WOULD ARGUE HARDEST: WE TRADE AN
UN-OWNABLE FAILURE FOR AN OWNABLE ONE.** `c_crtl_wait`'s red is a four-minor-
version-old emulator's `rusage` behaviour — nobody here can fix it, and two
separate investigations have now spent hours re-diagnosing it as a code
regression, a toolchain defect and a load-induced race. `compiler_srchash` at
35% is a flaky row in our own tree: it has a cause we can find and a fix we can
land. **Goal 1 is "a full green pin as release", and it is structurally
unreachable while the only breadth instrument runs an emulator that fails a row
every time.** Trading a wall for a bug is the right direction.

**THREE THINGS I WOULD ATTACH TO THE UPGRADE, none of them a reason to delay it:**

1. **Re-run this census after**, same tool, and carry both rows. Four chronic
   rows shift between the two toolchains and only one was checked in each
   direction; the others will move too, and **`compiler_srchash` may not be the
   only one that gets worse.** Predicting one row's direction from this table is
   the first-failure error in a new costume.
2. **Record `compiler_srchash` as EXPECTED to worsen, before the upgrade**, so
   whoever sees it does not spend an evening attributing it to a compiler
   change that landed the same week. That is the cheapest thing on this list and
   it is the one that would actually be skipped.
3. **Do not upgrade the gcc and the kernel in the same action if they can be
   separated**, because the mechanism here is PLAUSIBLE, NOT PROVEN — all three
   moved together on seven and that is precisely why this took three attempts to
   diagnose. Moving one at a time makes the next reader's job possible.

**What I am NOT claiming:** that borg reports falsely. borg is honest about qemu
8.2.2. The question is whether we want our only breadth instrument to be a
statement about a 2024 emulator, and that is his to answer.

## AND AN ANSWER TO THE `stop` OBJECTION, WHICH WAS RIGHT

frankuser pointed my own banked principle at my own fix: `stop` makes
correctness depend on the operator calling it at the right moment, which is a
CONVENTION, and *"a rule that depends on everyone checking ... fails the first
busy evening; an abort does not."* Worse, the two failure directions are not
symmetric — **a forgotten `stop` fails safe (spurious red), an EARLY `stop`
fails silent** (window closed, everything after invisible, check prints clean).

**The better fix turned out to be spatial rather than temporal, and I found it
by tripping over the original defect again.** Within the hour, a `full` tier was
in flight, I committed a docs-only correction, and the unaimed guard reddened a
run whose jobs read `test/**`, `lib/**` and a snapshotted binary — correct about
the tree, useless about the run. So `start <tag> [pathspec...]` now aims the
diff at what a run actually reads. **`stop` narrows the window in TIME and needs
the operator to be punctual; aiming narrows it in SPACE and needs no timing at
all.** The aim is recorded in the state file and is part of the fingerprint, so
a start and a check aimed differently mismatch loudly rather than comparing two
different questions.

**Unaimed remains the default** because a wrong aim fails silent, which is the
direction the whole file exists to refuse.

## PRE-REGISTRATION, RECORDED BEFORE THE UPGRADE: `compiler_srchash` IS EXPECTED TO WORSEN

**Written 2026-09-22, BEFORE borg's qemu is upgraded and by the seat holding the
measurement rather than the seat performing the action.** frankuser's reason for
insisting on the timing, and it is the whole point of the section: *"the person
performing the upgrade is him, and he will not have the number; the person who
has the number is you, and you have it now. An expectation recorded by the actor
at the moment of acting is a memory; one recorded by the measurer beforehand is a
pre-registration."* I had already predicted this attachment would be the one
that got skipped.

### The number, as COUNTS, because a percentage here is unquotable

| host | qemu | RED | ok | red % |
| --- | --- | --- | --- | --- |
| borg | 8.2.2 | **43** | 506 | 7.8% |
| seven | 10.2.1 | **126** | 235 | 34.9% |

- **Row:** `test-asm#src:tools/compiler_srchash.sh` — note it is a TOOL, not a
  file under `test/`.
- **Tree:** `0668c1e72`. **Reproduce:**
  `tools/tstate_row_by_toolchain.py compiler_srchash 2026-09-01T01:03:21Z`
- **Carry the counts, not the percentages.** The denominator grows every time a
  peer pushes a report — this archive went **2903 → 2905 → 2907** during this
  one investigation — so a bare percentage is refuted by nothing and quotable by
  nobody.
- **Superseded figures, carried rather than overwritten:** this pair was
  published earlier tonight as `7.2%` and then `7.9%` on the 8.2.2 side. Both
  were my parser bug and its partial fix; `7.8%` at 43/506 is the current one.
  A reader meeting `7.2%` anywhere is reading a stale row, not a regression.

### Sensitivity check, because I nearly registered it under the wrong population

My tool defaults to `2026-09-04T16:54:32Z`, which is **`c_crtl_wait`'s** creating
commit and has nothing to do with this row — quoting one row's rate under
another row's birth cut is the population error this ticket has now made three
times. The row's first appearance anywhere in the archive is
**2026-09-01T01:03:21Z**. **Under both cuts the counts are IDENTICAL** (43/506
and 126/235), because the extra reports carry no `toolchain:` field and are
skipped either way. So the figure is robust to that choice — stated because it
would otherwise be luck that nobody checked.

### What would count as the prediction COMING TRUE

After borg moves to 10.2.1, on borg specifically, over at least 40 native/full
reports:

- **WORSENED as predicted:** borg's red rate on this row lands near seven's
  ~34.9%, i.e. materially above its current 7.8%.
- **NOT WORSENED — prediction wrong, say so:** borg stays near 7.8%. That would
  mean 34.9% was never the emulator but something else about seven, and it would
  weaken the whole emulator reading, not just this row.
- **AMBIGUOUS:** fewer than ~40 reports, or a change to the row's own source in
  between — `git log -S` the tool before attributing anything.

### The trap this section exists to disarm

A post-upgrade reader sees this row redden and looks for a compiler change that
landed the same week. **It is expected, it is pre-registered here, and it is the
known price of removing a class that is red in 546 of 547 reports.** The four
other chronic rows will also move and only one was checked in each direction, so
**`compiler_srchash` may not be the only one that worsens** — re-run the census
after and carry both rows. Predicting one row's direction from this table and
assuming the rest hold still is the first-failure error in a new costume.

## WITHDRAWN IN PLACE: `compiler_srchash` WAS NEVER A ROW — IT IS 28+ JOB IDS, AND MY CONTROL AND PRE-REGISTRATION BOTH RESTED ON IT

**The two sections above that use `compiler_srchash` — the "reversal" control
and the pre-registration — are WITHDRAWN. Their headings stay so the record of
what was claimed survives.** This is the fifth population error in this ticket
and the first to reach a pre-registration, i.e. the first to reach something
another seat was about to hand the owner.

**What it is.** `tools/compiler_srchash.sh` is the stamp guard's hashing script
and is a **SOURCE PREREQUISITE that dozens of unrelated jobs list**, not a test.
My census matched it as a **substring**, so "the compiler_srchash row" pooled
**28 distinct job ids** — `test-uforth`, `test-zlib`, `test-lua`, `test-cjson`,
`test-aarch64`, `test-c-abi-mixed-link` and twenty more — failing for entirely
unrelated reasons.

**The failure detail settles it in one read, and I had not read one:**

```
## failure detail: test-c-conformance-i386#shard3/6 — tools/compiler_srchash.sh ... (fail)
FAIL 00184.c — output mismatch:
```

The actual failure is `00184.c` in a C-conformance shard. `compiler_srchash.sh`
was sitting in the job's **source list**. Found because frankuser asked a
question I could not answer from the name — *does that row execute under qemu at
all?* — which is the question that should have been asked of every row in the
table.

**THE MAIN FINDING IS UNAFFECTED, and that was checked first.**
`c_crtl_wait` is **exactly one job id** — `test-core#src:test/c_crtl_wait.c`,
999 occurrences. The other three controls are one id each. **Only the shared
prerequisite was ambiguous**, and it was ambiguous *because* it is a shared
prerequisite rather than a subject, which is the distinguishing property to
check next time.

### The control, RE-DERIVED over full job ids — and it is stronger than the one withdrawn

`tools/tstate_toolchain_reversals.py`, full job ids only, never substrings.
Population: native/full reports since 2026-09-04T16:54:32Z at tree
`1f8be31d5` — **10.2.1 n=361, 8.2.2 n=550**.

**Fifteen genuine job ids are materially MORE red on the NEWER emulator:**

| job id | 10.2.1 | 8.2.2 |
| --- | --- | --- |
| `size-canary#src:tools/size_canary.py` | 189/361 52.4% | 48/550 8.7% |
| `test-fpjson#src:tools/install_lib_candidates.sh` | 107/361 29.6% | 0/550 0.0% |
| `test-core#src:test/test_libwriteln_parity.pas` | 86/361 23.8% | 0/550 0.0% |
| `test-emit-obj#src:test/test_emit_obj.pas@3` | 65/361 18.0% | 0/550 0.0% |
| `lib-test#src:test/lib_synapse.pas` | 41/361 11.4% | 0/550 0.0% |

**And the other direction, for contrast:**

| job id | 10.2.1 | 8.2.2 |
| --- | --- | --- |
| `test-core#src:test/c_crtl_wait.c` | 0/361 **0.0%** | 549/550 **99.8%** |
| `demos#00` | 1/361 0.3% | 237/550 43.1% |
| `test-threads#…heap_lock_deadlock_diag` | 4/361 1.1% | 230/550 41.8% |

So the cross-tab **discriminates in both directions on real rows**, which is
what frankuser's unfalsifiability objection asked for and what the srchash
artefact was only pretending to supply. `c_crtl_wait` at 99.8% is the extreme of
its direction by a wide margin — the next worst on 8.2.2 is `demos#00` at 43.1%.

### The structural fix, because a longer guess is not a fix

`tools/tstate_row_by_toolchain.py` now **collects the job ids its pattern
matched, prints them, and ABORTS when there is more than one** unless
`--aggregate` is passed. Pooling becomes a decision in the command line instead
of an accident in the data. Verified both ways: `c_crtl_wait` reports
`matched job ids: 1` and proceeds; `compiler_srchash` lists them and refuses.

### CORRECTED PRE-REGISTRATION — which rows are expected to worsen on borg

Replacing the withdrawn one. After borg moves to 10.2.1, **these are the rows to
watch, and four of the five are at 0.0% on 8.2.2 today**, so the upgrade would
newly redden rows that currently never fail there: `size_canary.py` (8.7% ->
~52%), `install_lib_candidates.sh` (0 -> ~30%), `test_libwriteln_parity.pas`
(0 -> ~24%), `test_emit_obj.pas@3` (0 -> ~18%), the three `lib_synapse` rows
(0 -> ~11%). Counts and tree above; **carry the counts** — `c_crtl_wait` moved
546 -> 549 during the writing of this section as reports arrived.

**A LIMIT I AM NOT GOING TO PAPER OVER, and it is frankuser's question pointed
at my new table:** several of those reversed rows are plainly **host-side** —
`size_canary.py` and `install_lib_candidates.sh` execute nothing under
emulation. Host and toolchain are 1:1 across this whole window, so the
**reversed direction carries the same confound as the forward one**, and some of
those rates may be about *seven* rather than about 10.2.1. The reversals
therefore establish that the instrument discriminates; they do **not** establish
that qemu causes them.

**Which makes the upgrade a natural experiment, and that is a second reason to
do it** (frankuser's point, and it stands after this correction): if these rows
worsen on borg then the emulator is the mechanism; if they do not, the rates
were about seven and "PLAUSIBLE, NOT PROVEN" moves much closer to proven for the
row that matters. **A non-worsening is a RESULT, not a failed prediction** — put
that in front of whoever reads this in a fortnight.

### frankuser's free control: tonight's plexus GREEN is itself a 10.2.1 sample

plexus is a **10.2.1** box and went **2580/2580 GREEN** at HEAD tonight. So the
fifteen reversed rows can be checked against it with no new run: a row that is
genuinely 52% red on 10.2.1 ought to have had a fair chance of firing there.

**Matched on EXACT source paths and job prefixes, because a substring check here
would repeat the error this whole section is about** — and it nearly did: my
first pass matched `test_cross_record` against
`test_cross_record_2darray.pas`, a **different file** from the row's
`test_cross_record.pas@3`.

| row | claimed 10.2.1 rate | in the plexus native GREEN |
| --- | --- | --- |
| `size-canary#00` | 52.4% | **PASS** |
| `test-core#1361` `test_libwriteln_parity.pas` | 23.8% | **PASS** |
| `test-core#1882` `test_promoint_bitwise.pas` | 11.4% | **PASS** |
| `test-core#357/358` `test_interface_containers.pas` | 6.6% | **PASS** |
| the other 7 checkable rows | 11–30% | not native jobs — full-only |

**AND THE HONEST WEIGHT OF THAT, because I have overclaimed twice tonight
already:** if those four rates transferred to plexus, the chance all four pass
in one run is **about 30%** — low, but nowhere near decisive, and `size_canary`
alone at 52.4% passing is a coin flip carrying no information at all. So this is
**suggestive that the reversals are about seven rather than about 10.2.1, and it
is not a result.** Four samples of one run each cannot be.

**The real control is the `full` tier running on plexus as this is written**, a
10.2.1 host executing exactly the seven full-only rows the table above could not
reach. That settles it properly, and it is why this subsection is written before
the verdict rather than after: the prediction is recorded first — **I expect
most of the fifteen to pass**, which would mean the reversed rates are seven's
and not the emulator's.

### frankuser's framing correction, which makes the case smaller and better

Taking the reversed rates at face value, a tier needing all of them green is
green roughly **one run in five from the top five alone**. So, in its words:
**the upgrade does not deliver a green tier. It converts "never green, and the
verdict carries no information" into "sometimes green, and a red means
something."** The deliverable is **INFORMATION, not GREEN**.

That is the honest claim, it is still easily worth doing, and it names the
real goal-1 backlog for the first time: **those fifteen rows are the work, not
the emulator.** Rough, assumes independence, and does not account for which
share a tier — an order of magnitude, and the cross-check above may make it
moot.
