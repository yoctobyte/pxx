---
slug: umbrella-one-full-tier-run-with-no-red-tier
track: T
prio: 55
type: umbrella
blocked-by: [regression-test-core-c-crtl-wait, bug-t-tstate-fingerprints-the-code-and-the-hardware-but-not-the-emulator-toolchain]
created: 2026-09-01
owner: frankZ
summary: "GOAL, not a unit of work: one `full` tier run with no RED in any tier judged at that sha. RE-RANKED 85 -> 55 on 2026-09-06: the prio-85 justification was that a green run makes the rollback target VERIFIED rather than merely recent, and CLAUDE.md now says the fleet does not roll back at all (owner, 2026-09-06: 'we avoid rollbacks. useful work done is work done'), usable rollback depth is ZERO, and verbatim `do not rank a ticket on rollback depth`. The other stated buy -- grading a pin `green` rather than `reds(N)` -- is voided by the same rule, which calls `pin_is_green`/`pinstatus` a target for an operation this fleet does not perform. What survives is ordinary regression value, and the goal itself stays reasonable: the reds are real defects. Lowering it DOES lower what its blockers inherit -- `effective_prio` (`tools/progress.py:945`) is max(own prio, dependents), so the floor they inherit from this goal drops 85 -> 55; what it cannot do is push any blocker below the prio it earned on its own, and that is the intended effect, not a side effect. CLOSER THAN IT HAS EVER BEEN: the newest full run on seven (`c543b335fb2f`, 2026-09-06T19:55Z) is RED on THREE jobs, down from nine in eight hours. Still ends when one clean run comes back; still not a standing triage desk."
---

# One full tier run with no RED tier

## 2026-09-06 — RE-RANKED 85 -> 55, and the goal is three reds away

frankH flagged the caveat and declined to re-rank on their own reading of a
rule, which was right: it is this umbrella's own justification, so it is mine.
Settled here rather than sent to U, because **U is for forks the rules do not
settle and this one is settled by the rules** — CLAUDE.md:207-214 does not
merely imply it, it names the operation:

> **WE AVOID ROLLBACKS — FORWARD IS THE RECOVERY PATH** (owner, 2026-09-06):
> *"yes we avoid rollbacks. useful work done is work done, even if (other)
> things break."* ... **do not rank a ticket on rollback depth.**

Both of this ticket's stated buys die on that. The rollback one is explicit.
The second — grading a pin `green` rather than `reds(N)` — dies to the same
sentence, which calls `pin_is_green`/`pinstatus` *"a target for an operation
this fleet does not perform."* v398 stays a good story and stops being a
ranking argument: what it argues for is pinning OFTEN, which is already a rule.

**55, not lower and not withdrawn.** The reds are real defects that would be
worth fixing with no umbrella at all; what the umbrella adds is order and
grouping.

**Say the cost plainly rather than reassuringly.** `effective_prio`
(`tools/progress.py:945`) is `max(own prio, eff(dependents))`, so this re-rank
drops the floor every blocker inherits from this goal by thirty points. It does
not push any blocker below its own `prio` — but "buries nothing" would have been
the comfortable phrasing of a real change, and the first draft of this section
said exactly that. **A ticket whose rank depended on the inherited 85 is
supposed to fall here.** If one of the three reds above turns out to deserve
more than 55, it earns that on its own body, which is where it should have been
all along.

### The state that argues for keeping it — measured, not inherited

Tonight's full runs on seven, in order (`## STILL-RED` + `## NEW-RED` counted
apart, because a bare `grep '^- '` merges `## FIXED` into the red list — that
error nearly filed a regression here on 2026-09-06):

```
17:47Z  77f298a   RED   still-red 9   new-red 0   fixed 0
18:02Z  c69b52b   RED   still-red 8   new-red 0   fixed 1
18:37Z  6d04b14   RED   still-red 3   new-red 2   fixed 3
19:43Z  1b903c1   RED   still-red 2   new-red 3   fixed 1
19:55Z  c543b33   RED   still-red 1   new-red 2   fixed 5      wall 600.8  flaky 7
```

Nine to three in eight hours, and in the last run the fix rate beat the arrival
rate five to two. This ticket's own standing condition is *"get one run where
the arrival rate loses to the fix rate for one tier's duration"* — that
happened tonight. The three at `c543b335fb2f`:

- `tools-devtest#00` — STILL-RED, and group 7 above already reports it fixed
  three times. Its fourth fault is the ticket to write, not a fourth fix.
- `lib-test#src:test/lib_sysutils_delphi_exceptions.pas` — NEW-RED tonight.
- `test-debug-g#src:tools/compiler_srchash.sh` — NEW-RED tonight, and the job
  name is a SELECTOR, not a label: `tools/compiler_srchash.sh` is merely the
  first source of the job, shared by several unrelated jobs. See
  [[bug-t-the-job-map-cannot-be-asked-whether-a-given-source-was-exercised]].

### And the archive claim, corrected in both directions

A peer read the archive as *zero shas with a full run and no RED, ever*. That
is false — 47 shas qualify, and this ticket's own body already said so
(*"588 shas have been fully green at some point"*). But the useful half of
their reading is the one neither of us stated: **every full GREEN in the
archive is plexus, borg or xeon; `seven` has never produced one.** The body
already explains why the goal can only be met there (*"the `full` run cannot
come from plexus — 41 jobs SKIP for missing corpus"*), so the two facts
together say the goal has never been met **by the only host that can meet it**.

That is worth stating plainly and is NOT yet a reason to call the goal
unsatisfiable in the sense of *"a gate that cannot pass is not a gate either"* —
tonight's 9 -> 3 is direct evidence against unsatisfiability. Revisit it if the
count stops falling; the discriminator is the trend, not the zero.

### The same rule lands on a ticket that is not mine — flagged, not re-ranked

Grouping rather than triaging: `ready --track T` puts
[[bug-t-the-named-rollback-target-cannot-build-the-tree-it-would-roll-back-to]]
at **prio 80**, and it is the ticket whose measurement *became* the CLAUDE.md
rule quoted above — usable rollback depth ZERO, every historical pin strictly
worse than the one in place. The rule's answer to it was not "fix the rollback"
but *"do not spend work making `make revert` produce a coherent pair."* So it
is ranked 80 for a remedy the owner ruled out, which is the same shape as this
umbrella's 85 and probably wants `low-prio/` or `rainy-day/` — its measurement
is true and reproducible, and there is no plan to act on it.

**Flagged, not moved.** frankH declined to re-rank this umbrella on their own
reading of a rule and handed it to its owner; that cuts both ways and the
symmetry is the point. Its neighbour
[[bug-t-pin-verify-builds-with-the-previous-pin-not-the-one-it-names]] is NOT
in this class and should stay at 80: it says every pin verify builds with pin
v(N-1) while recording the verdict under vN. That is an instrument lying about
which binary it measured, and it is wrong whether or not anyone ever rolls back.

Written 2026-09-01 by frankZ, from the owner's words via frank-user: *"we
should have one track working on the regressions, and only the regressions."*

## What this buys, stated accurately

The original framing for this umbrella was that the pin's recovery leg was
*dead*. That was too strong and CLAUDE.md has since settled it: **a valid pin
is the self-host fixedpoint and nothing else may block one** (owner,
2026-09-01), pins are GRADED (`green`, or `reds(N)` with the manifest) rather
than gated, and rollback *"prefers a green pin and falls back to the most
recent, so recovery is never empty."*

So nothing is blocked and nothing is empty. What a green run actually buys is
that the rollback target becomes **verified** instead of merely **recent** —
the difference between falling back to a pin known to be sound and falling
back to the last one taken. v398 is the argument for the distinction: it
shipped a compiler that could not build C for i386 or arm32, and every
`$(PXX_STABLE)` consumer carried that for two days.

Worth having. Not an emergency, and this ticket should not be quoted as one.

## What "green" actually means here, measured

`tools/trackt.py:1525`:

```pascal
def pin_is_green(runs_for_sha):
    """Judged by T, with a `full` run, and nothing RED in any tier judged."""
```

Two conditions, and the second is the one that surprises people: **every tier
judged at that sha must be GREEN, not just `full`.** `opt` is disjoint from the
quick<native<limited<full chain and runs only as idle watcher work — but it
co-occurs with `full` on **704 of the 1234 shas that have ever had a full
run**, so a red `opt` tier does count against roughly half the candidates.
`optdiff` lives in `opt`; that is why it is wired here.

Also measured, because the two get conflated: **588 shas have been fully green
at some point, the most recent `90892318c94c` on 2026-08-26.** The twelve-day
figure is about *pinned* shas, which is a strictly smaller set. Fixing the reds
is necessary; it is not sufficient, because the pin also has to be verified at
a sha that carries the run.

## How this umbrella grows — attempt, do not triage

Run the tier. Every RED it returns names a ticket, in the order it actually
costs. Nothing gets wired here because it looked related.

**Re-lane before working.** An auto-filed regression carries `track: T` (or a
track guessed from the failing STEP) as a FALLBACK, not a finding, at a prio
nobody set. T owns the TOOL, never the BUG. Thirteen of these accumulated with
nobody on them for exactly that reason.

## The groups — state at 2026-09-02, binary sha256 `b9fd008f89ef`, commit `77d627edb`

{ `77d627edb` replaces the pre-rebase ghost `cdefc55e1`, which was on no remote
  ref. Derived rather than guessed: that string was introduced BY `77d627edb`
  (`git log -S`), so the ghost was this commit's own local id before the rebase
  that landed it. The usual self-versus-parent ambiguity is immaterial here —
  `77d627edb` touches no `compiler/` or `lib/` file, so its tree and its
  parent's are identical for every build input, and the binary above was built
  from both. A binary sha256 is not a commit, so it is now labelled as one. }

Report by group. A count of tickets is not a count of causes. **Thirteen of the
fourteen tickets wired here at the start are resolved, and they were six
causes.**

1. **`-O3` DCE miscompiles every threaded program** — five optdiff shards, ONE
   bug. FIXED (`dce.inc`'s `GlobFix[]` compaction dropped the three arrays
   parallel by index to it). The masking half — optdiff could not build any
   threading program — is fixed too, and it turned out to be two harness holes
   rather than one: the `-O2` arm was comparing `-O2` against `-O2` and could
   not fail. Both closed.
2. **Threading correctness in the RTL** — `thread_api_no_uses` was a missing
   `--threadsafe` on its recipe. `refcount_lockfree` and
   `exception_threads_race` belonged to group 5, not here.
3. **crtl / C headers** — all three fixed.
4. **xtensa PAL** — one missing constant (`PAL_ERR_UNSUPPORTED`), both fixed.
5. **Managed memory / the ownership campaign** — four reds, **two causes**, not
   four: the park firing on already-owned values, and an interface
   function-result temp on the wrong queue. frankB's `d5e0a1e48`. Re-derived
   here at `c9602d5ce` rather than inherited; all four green.
6. **`optdiff#shard4`** — never the same bug as group 1, as frank-user said.
   Not a bug at all: the program's output order is nondeterministic by design
   and its property is atomicity, which raw stdout cannot express. Skiplisted;
   the invariant verified at all four levels, 20 runs.
7. **`tools-devtest#00`** — three faults, and the third only existed once the
   first two were fixed: a devtest whose verdict depended on the developer's
   own tree, a Makefile row that put the pinned compiler in the NATIVE tier,
   and then a 90s budget against 207s of work, because the job had been red
   long enough that no green pass had ever been measured.

**Two causes found by attempting the target rather than by triage**, which is
what this umbrella is for:

- **The heap magazine, shared by every thread pxx did not create.** A libc
  pthread never runs the clone stub, so it inherits its creator's `gs` —
  `gs_base = 0x411f98` (BSS_TLS_MAIN) on all five threads of
  `test_multithreading`. The guard was a plain load-test-store. 18 SIGSEGV in
  100 runs, 0 in 100 with `-dPXX_NO_HEAP_MAG`. Fixed (`ba2682d2f`); the design
  residual is
  [[bug-a-a-foreign-thread-shares-the-main-thread-s-heap-magazine]].
  **Not a regression** — the pinned v399 compiler builds a byte-identical
  program that crashes the same way.
- **The one still open:**
  [[bug-a-a-refcount-test-passes-at-o2-and-fails-at-o0-and-o1]] — FAILED at
  -O0/-O1, OK at -O2/-O3, `rc=0` throughout. Found by the fixed sweep on its
  first run that could see the program at all.

## The `opt` tier is GREEN — 17/17, one run, nothing moving under it

2026-09-02, frankZ. `testmgr --tier opt`, binary `0f1d03315f4eaaa7`,
`converged after 1 round(s)`, commit `1236bf31f`:

```
17/17 pass
testmgr: GREEN
HEAD_BEFORE = 1236bf31f93084fe...
HEAD_AFTER  = 1236bf31f93084fe...     (recorded, not assumed)
```

**Why the before/after pair is in the record.** Two earlier attempts at this
number were discarded, both contaminated by me and neither by anyone else. The
first straddled a `git pull` I ran mid-sweep while looking for newly arrived
regressions — the compiler was snapshotted at one commit while optdiff read
test sources from a tree that had moved. The second was worse: I edited
`tools/optdiff.sh` and `optdiff.skip` while the sweep was executing them, and
`/bin/sh` reads a script incrementally, so all three shards returned `rc=2` —
a shell parse error wearing the shape of a verdict. **An exit code no test in
the harness can produce is the signal to suspect the instrument, not the
subject** (now a rule, `d27c304e1`).

So this run states its own scope: one tier, one commit, one binary, and the
tree provably unchanged across it.

## What a green `opt` does and does not buy

`opt` is DISJOINT from the quick<native<limited<full chain. `pin_is_green`
requires a `full` run at the sha AND every judged tier green, so this removes
one of two conditions and says nothing about the other.

It is also not the same claim as the last green `opt` anyone recorded, and the
difference is the point: **the previous sweep could not build any threading
program** (they were BUILD-FAIL skips without `--threadsafe`) **and its `-O2`
arm compared `-O2` against `-O2`**, which could not fail for any program in the
corpus. Green from a sweep that can see the programs is the first green here
worth anything.

The `full` run cannot come from plexus — 41 jobs SKIP for missing corpus
(`library_candidates/*`, `external/synapse`). It arrives on Track T's cadence
from seven; it is evidence to watch for, not work to perform.

## The second wave — 2026-09-02, and it is the umbrella working, not failing

The fourteen tickets wired at the start are all resolved. **Eleven new ones are
wired now**, and that is the point of the shape rather than a setback: an
umbrella grows by ATTEMPTING THE TARGET, and each pass names the next set in
the order it actually costs. What arrived between the first sweep and this one:

- **`test-pascal-conformance` shards 0-3** (four) — one job shape, almost
  certainly one cause. Group before working.
- **`lib-test lib_synapse`** ×3 — **cannot be reproduced on plexus at all**:
  `external/synapse` is one of the 41 jobs that SKIP here for missing corpus.
  These need seven or the corpus.
- **`test_exception_unhandled` and `test_setlen_in_parallel_for_body`** — do
  NOT reproduce here on EITHER compiler: 0 failures in 40 runs at HEAD and 0 in
  30 under the pinned v399, byte-different programs both times. Seven runs them
  under full-matrix parallelism and I ran them solo, which for
  threading-adjacent programs is the likeliest difference. Half a finding; the
  residual is Track T's and is named on both tickets.
- **`regression-cascade-fc01c8094434`** and the three NilPy dispatch tests,
  neither triaged here.

**Two of tonight's reds were not regressions and both had EMPTY bisect ranges**
— every commit in the window touched only docs. That is not missing paperwork,
it is the finding: `test_multithreading` had been failing since the heap
magazine landed, and the pinned v399 compiler builds a byte-identical program
that crashes at the same rate.

## The count is not falling on its own

Native reds on seven went **2 → 7 between 19:13Z and 20:11Z on 2026-09-01**,
from ordinary lane work landing. That is the standing condition this umbrella
is measured against: the target is not "fix thirteen things", it is "get one
run where the arrival rate loses to the fix rate for one tier's duration."

## Do not

- **Never `make pin`.** Irreversible, and the owner's alone.
- Do not widen this into a triage desk. One clean run and it closes.
- Do not read a shrinking red count as progress without checking whether the
  job still RUNS. Group 1 is exactly that failure mode.

## The conformance group is closed — four tickets, two causes, neither ours

2026-09-02, frankZ. `fpc-testsuite @ 0d122c49534b48` fetched to plexus (it was
one of the 41 jobs that SKIP here for missing corpus, which is why the first
pass at this group could only hypothesise and correctly refused to skiplist on
a hypothesis).

**All six shards green in one run, tree provably unchanged across it.** Binary
`0f1d03315f4eaaa7`, commit `922dfa971`:

```
shard 0/6   62 pass, 0 fail, 25 skip, 5 auto-gated (of 92)
shard 1/6   63 pass, 0 fail, 24 skip, 5 auto-gated (of 92)
shard 2/6   50 pass, 0 fail, 36 skip, 6 auto-gated (of 92)
shard 3/6   57 pass, 0 fail, 29 skip, 6 auto-gated (of 92)
shard 4/6   61 pass, 0 fail, 25 skip, 5 auto-gated (of 91)
shard 5/6   56 pass, 0 fail, 28 skip, 7 auto-gated (of 91)
HEAD_BEFORE = 922dfa971e21c7e0...
HEAD_AFTER  = 922dfa971e21c7e0...     (recorded, not assumed)
```

Four tickets, **two causes, and I fixed neither**:

- **shard0** — `tgeneric32`/`tgeneric49`, both `(compile)`. Fixed by claude-T on
  2026-09-01 and written up on the ticket. It stayed wired here for a day
  because the body said RESOLVED while the frontmatter still said
  `status: backlog`. **A ticket that says RESOLVED in prose is not resolved to
  anything that reads frontmatter**, and the ranker reads frontmatter and
  nothing else.
- **shards 1/2/3** — nineteen `tgenconstraint*(accepted-invalid)` rows, one
  construct: a generic specialized with an argument its constraint rejects.
  Fixed by **`f4fb9d31b`, the owner's own commit**, 2026-08-30 15:56Z — *six
  hours after the shards were filed at 09:59Z the same day*. They then sat open
  for three days at prio 70 in Track T, a lane that could not have fixed them.

**What this group cost was routing, not engineering.** Both causes were fixed by
other people before anyone read the tickets; the umbrella's only real work was
finding that out. The filer's `track: T` fallback is the mechanism and it is
argued, with this as the evidence, on
[[chore-t-fpc-conformance-noise-skews-priority]] — where I agree with option 1
(route to `P`, split by the failure KIND the runner already prints) and disagree
with option 2 (pin-allowlist), because allowlisting would have muted exactly the
nineteen the owner acted on.

**Three `pxx.skip` rows had gone false** in the same fix and were deleted:
`tgenconstraint38`/`39`'s `wontfix: PXX does not enforce generic constraints`
(it does, since `f4fb9d31b`) and `tgenconstraint1`'s `gap:` (it compiles). A
skip row is a capability claim the runner obeys and nothing re-reads. Only
`tgenconstraint37` keeps its `gap:`, and it is real.

## The synapse group — three jobs, ONE construct, and the corpus was the blocker

2026-09-02, frankZ. These three sat here as *"cannot be reproduced on plexus at
all"* because `external/synapse` is one of the 41 jobs that SKIP for missing
corpus. `tools/install_externals.sh` fetches it (synapse @ `b3224c3d133a`).
**All three reproduce on the first try and all three are one construct.**

`external/synapse/ssfpc.inc`, in `WSAStartup`'s `with WSData do`:

```pascal
szDescription  := 'Synsock - Synapse Platform Independent Socket Layer';
szSystemStatus := 'Running on Unix/Linux by FreePascal';
```

`ASTCharArrayCap` — the ONE oracle the char-array-is-a-string conversion asks,
in both directions and at every site — answered only for `AN_IDENT` while its
header said it answered about a NODE. A record FIELD got -1, the conversion
never fired, the store fell through to the scalar type check, and
`cannot assign ShortString to Char` is what that check correctly says when it is
asked to put a string into a Char. **Five of six lvalue shapes refused; the
plain variable was the only one that worked.** Fixed at `9c6b216aa`
([[bug-p-a-char-array-through-a-field-or-a-deref-is-not-a-string]]); FPC 3.2.2
is the oracle for all 14 rows of the new test, and the pinned compiler rejecting
that test is its positive control.

**The three JOBS stay wired and stay RED.** Their recipe builds with
`$(PXX_STABLE)` and the pin still carries the bug — nothing in this tree can
turn them green, so resolving them would claim a verdict the job cannot return.
They close when the owner pins. **That is not a reason to pin**, and nobody
should take one to close a ticket.

## The three NilPy dispatch tests are green — resolved

Binary `090042338fc2deae`, commit `9c6b216aa`, all three PASS against their
`.expected` files, with a negative control run (one test's output against
another's expectation reports a difference, so the comparison can fail). Solo
rather than under seven's parallelism, which does not matter here: that ticket's
own diagnosis established these as deterministic COMPILER bugs. The fixing
commit is not named and is not guessed — 779 commits touched `compiler/` in the
window.

## A harness lesson, mine, worth more than the sweep

Checking the cascade's 24 NilPy jobs, I compared each program's output against
`test/<name>.expected` and got **11 failures**. All eleven were exactly the
tests that have **no `.expected` file** — the Makefile compares them against an
inline `printf` string instead. `diff` against a missing file errors, and my
loop read that as a failing test.

`test_nilpy_optional_param` then passed in 2.1s under the real recipe.

Same shape as the two contaminated runs recorded above and as
`d27c304e1`'s rule: **an instrument that answers about something else does not
error, it answers.** The fix was to stop hand-rolling the comparison and run
`testmgr --job` — the thing that owns the recipe. `PXX_ALLOW_FULL_SUITE=1` is
what a single-job run past the quick tier costs, and it is a SPEED guardrail,
taken autonomously.

## The cascade is green — 38/38, and nothing named it

`regression-cascade-fc01c8094434` resolved. 32 jobs run here through
`testmgr --job` (32/32 GREEN, binary `23e9a1d6a3775ac2` unchanged across the
sweep), five conformance shards already green above, `tools-devtest#00` closed
earlier on this umbrella. **Two controls**, because a sweep that ran nothing
reports like a sweep that passed: the row count asserted at 32 both sides, and
an unmatched `--job` proven to print `no jobs match` and exit 1 rather than
GREEN.

No cause named. The 87-commit range was never bisected — the watcher skips
cascades by design — and picking a plausible commit out of it would be
attribution by topic.

## What is left, and it is two kinds of nothing-to-do

Five blockers remain and **none of them is work anyone can perform here**:

- **Three `lib_synapse` jobs** — cause found and FIXED in tree (`9c6b216aa`),
  but they build with `$(PXX_STABLE)` and the pin still carries the bug. They
  go green on the next pin and not before. Not resolved, deliberately:
  resolving would claim a verdict the job cannot return.
- **`test_exception_unhandled` and `test_setlen_in_parallel_for_body`** — do not
  reproduce here on EITHER compiler (0 in 40 at HEAD, 0 in 30 under the pin,
  byte-different programs). Half a finding, and Track T owns the residual,
  which is named on both tickets.

So the umbrella's own condition — *"no wired blockers and the causes are
fixed"* — is met for everything a session on this box can reach. The green
`full` run is evidence that arrives from seven, not work performed here.

## The third wave — SEVEN jobs, ONE cause, and the cause is a good commit

2026-09-02, frankZ. Eight regressions arrived that nobody had wired here. Seven
of them are **one commit**: `00ab464bf feat(C,B): the C frontend announces GNU C
2.7`.

That commit is right and is not being second-guessed. It fixed a **silent wrong
layout** — with no `__GNUC__`, glibc's `<sys/cdefs.h>` defines `__attribute__`
away, so PACKED / ALIGNED / NORETURN expanded to nothing and a libarchive gzip
header union came out 12 bytes where gcc makes 8. Its stated trade is loud
compile failures naming the construct in exchange for no quiet wrong answers,
and that trade is one-directional. What it did not have is the size of the loud
half: it measured *"busybox's 265 translation units: 1 fixed, 0 broken."*
**Across the tier it is 7 broken**, and busybox was simply the wrong corpus to
look in.

- **Five `test_c_gtk*`** — `__builtin_constant_p`, which glib reaches on a bare
  `__GNUC__ >= 2` gate (`gstrfuncs.h:311`). It is a **2.x** builtin, so the 2.7
  claim turns it on even though that version was chosen to keep 3.x/4.x builtins
  off. **FIXED** — reduced to the integer literal 0 beside `__builtin_expect`,
  which is the arm every non-GCC compiler takes. All five GREEN under
  `testmgr --job`, which owns the recipe (three run under `xvfb-run` and one
  greps `readelf -d`; a hand-rolled comparison would have done none of that).
  Re-laned P→C.
- **Two `test-lua*`** — labels-as-values. Lua 5.4 gates its computed-goto
  interpreter loop on a **bare `#if defined(__GNUC__)`**, no version test, so it
  reaches `ljumptab.h`'s `&&L_OP_MOVE`. **NOT fixed** — it is a real C-frontend
  feature and it is [[bug-c-labels-as-values-is-the-whole-of-the-lua-regression]],
  wired here. Proved to be the ONLY blocker in both directions:
  `-DLUA_USE_JUMPTABLE=0` and `-U__GNUC__` each build the runner, and the binary
  passes 6/6 lua programs. Two proofs rather than one because they fail
  differently — one isolates the construct, the other the cause.

The eighth, `regression-test-core-c-crtl-mount-and-prio`, is wired here untriaged.

**Sequenced with frankD**, who owns `00ab464bf` and the lane: told before
touching `cparser.inc`, not asked. Their reply supplied the one shape the
always-0 reduction is wrong for — `BUILD_BUG_ON(!__builtin_constant_p(x))`,
which becomes a negative array dimension, i.e. still loud — and it is named in
the source comment so nobody rediscovers it.

## The eighth was not a regression at all

`regression-test-core-c-crtl-mount-and-prio` — a **first-ever red**, which the
stub itself flags: no earlier passing sha, so no interval contains a cause. The
expectation demanded two backslashes where the C source writes one
(`"/mnt/back\\slash"` is ONE backslash in C) because the Makefile's `printf`
carried an extra escaping level that had never been executed.

**Decided by an oracle, not by counting escapes.** Comment-versus-code says one
side is wrong and you do not know which, so rather than reason about the
make→shell→printf chain I ran gcc on the same source: it prints one backslash,
and pxx matches gcc on **all ten rows**, diffed whole. Fixed the string, `1/1
pass`. `c3abc58f2`.

## State of the umbrella, and what each blocker is waiting on

| blocker | waiting on |
|---|---|
| three `lib_synapse` jobs | **a pin.** Cause fixed at `9c6b216aa`; they build with `$(PXX_STABLE)`. |
| `bug-c-labels-as-values-...` | **frankD**, who has taken it. A real feature: an address-of-label relocation the object writer does not emit, and an indirect-branch node the IR's control flow lacks. |
| `test_exception_unhandled`, `test_setlen_in_parallel_for_body` | **Track T.** Do not reproduce here on either compiler; the residual is named on both. |

Nothing on that list is work a session on this box can perform, which is the
condition this umbrella was given: *"your job ends at 'no wired blockers and the
causes are fixed'; the green full run is evidence that arrives, not work you
perform."*

Two things may move the count on their own, both frankD's and both landing
without my involvement: the widened const-branch fold (a dead
`if (__builtin_constant_p(x) && ...)` arm kept its calls as real external
references, because the `x and 0` identity read the OUTER binop while the C
frontend wraps unsigned results in a width mask — so the real shape is
`and(and(x,0),0xFFFFFFFF)` and nothing folded), and busybox rung 3 going green
at 141 applets / 265 objects, byte-identical to gcc over 387 cases.

## THE TARGET IS PARTLY A LOTTERY — two of the blockers FLAP

2026-09-02, frankZ, from Track T's own archive rather than from any run of mine.
Counting every tstate commit subject that names each test:

| test | NEW-RED-bearing | FIXED-bearing | total markers | concentrated in |
|---|---|---|---|---|
| `test_exception_unhandled.pas@3` | 10 | 11 | 24 | 18 of them on 2026-09-01 |
| `test_setlen_in_parallel_for_body.pas` | 10 | 10 | 20 | **all 20 on 2026-08-31** |
| `test_multithreading.pas@1` | 3 | 3 | 6 | all on 2026-09-01 |

**A regression cannot be fixed and re-broken ten times in one day.** That needs
ten fixes and ten breakages, on one host, across shas that mostly touch docs and
tickets. The verdicts are nondeterministic and the watcher is faithfully
reporting a coin.

This is a **second source that fails differently** from the local
non-reproduction already recorded above. 0-in-40 here is equally consistent with
"rare flake" and with "host-specific bug" and cannot separate them; alternating
markers on the SAME host can, because a host-specific bug is stable on its host.

### What it means for this umbrella's own goal

The target is *one* `full` run with no RED in any tier. Two of the remaining
blockers decide their own verdict on each run. **So the target is not reachable
by fixing alone** — the arrival rate can lose to the fix rate and the run still
comes back red, at odds nobody has measured. Recorded because it changes what
"done" means here: either the two are stabilised (a real race in the program is
the likely cause and would be a far more valuable ticket than these two), or
they are quarantined with a citation the way `pin-allowlist.tsv` is designed
for — and I have argued AGAINST casual allowlisting elsewhere on this umbrella,
so I will say plainly that a MEASURED flake is the one case the mechanism is
actually for.

Neither is mine to decide: it is Track T's tool and Track T's call, and the
residual is named on both tickets. What was missing was the measurement, and it
is no longer missing.

**Do not bisect either of them.** There is no cause in any commit range; the
auto-filed range is not unnarrowed, it is meaningless.

## The six `optdiff` reds on seven are STALE — they predate fixes already landed

2026-09-02, frankZ. `twatch --status` lists five `optdiff#shard{0,1,2,3,5}/12`
reds, and seven's own run archive adds a sixth (`shard4/12`) that the summary
does not list. **All six are already fixed. Seven has simply not re-run the
`opt` tier since 2026-09-01T10:08Z.**

### Not a flake — the archive says so, and the method has a control

The same marker count that proved the threading tests flap says the opposite
here: each of the five has **one NEW-RED and zero FIXED**. Went red once,
stayed red. `optdiff#shard4/12` has zero markers, which is the negative control
— the method distinguishes, rather than answering "flake" for everything.

### What they actually were, from seven's own report

`tstate/reports/20260901T071328Z-a5f0958-seven.md`, one shape in every shard:

```
OPT DIFF -O3: test/test_thread_api_no_uses.pas          (rc 0 vs 124)
OPT DIFF -O3: test/test_threadsafe_heap_lock_release.pas (rc 0 vs 124)
OPT DIFF -O3: test/test_threadsafe_layout_rtti.pas       (rc 0 vs 124)
OPT DIFF -O3: test/lib_criticalsection_blocking.pas      (rc 0 vs 124)
OPT DIFF -O3: test/lib_fpc_thread_surface.pas            (rc 0 vs 124)
OPT DIFF -O3: test/lib_classes_tthread.pas               (rc 0 vs 124)
```

**`rc 124` is a TIMEOUT: threading programs HANG at `-O3`.** That is
`bug-a-five-optdiff-shards-are-one-o3-threading-hang` — group 1 at the top of
this ticket — the DCE `GlobFix[]` compaction dropping the three arrays parallel
to it. Fixed at `0afbd1f7f`. And `shard4/12`'s STILL-RED is
`test_threadsafe_io_lock_foreign.pas`, the atomicity family, `5136f3450`.

Both fixes are **later than the red**: the red sha `a5f0958c6934` is
2026-09-01T07:13Z, `0afbd1f7f` is 21:42Z and `5136f3450` is 2026-09-02. `git
merge-base --is-ancestor` says NO for both.

### Measured here, all six shards, provenance either side

```
shard 0  pass=170 skip=19 diff=0      shard 3  pass=154 skip=22 diff=0
shard 1  pass=163 skip=26 diff=0      shard 4  pass=169 skip=26 diff=0
shard 2  pass=159 skip=18 diff=0      shard 5  pass=137 skip=33 diff=0
                                      TOTAL   pass=952 skip=144 diff=0
HEAD_BEFORE == HEAD_AFTER == 9df0058fe    BIN unchanged == 056bf9cd55f97e41
```

**The guard is aimed, not just read.** Six of the seven named programs were
proven COMPARED, all six through the `--threadsafe` retry arm — which is itself
`1b65bac9e`, the fix that made them visible at all; before it they were
BUILD-FAIL skips and no sweep could have seen the hang.

### Two scope limits, stated rather than implied

1. **`shard4` is green because the program is SKIPLISTED, by me.** That is not
   "the divergence is fixed". Its property is atomicity and raw stdout cannot
   express it; the invariant was verified separately at all four `-O` levels
   over 20 runs. Do not read that row as a repair.
2. **Three programs this box cannot build are compared on seven and skipped
   here** — `cquickjs_prereq.c`, `csqlite_layout_probe.c`,
   `csqlite_extended_test.c` — so this green does not cover them.

### An error of mine, in the check itself

My first pass "verified" all seven named programs were compared. One,
`test_threadsafe_io_lock_foreign.pas`, lives in **shard4, which I had not run** —
so "no skip row names it" meant *the shard never executed*, and I read it as
*the program was compared*. **Absence of a skip row is not evidence of
comparison.** Caught by asking which shard the file hashes into; fixed by
running shard4, where it duly appears as a SKIPLIST row. Same family as the two
instrument errors above, and the third today.

## Labels-as-values closed by frankD; one new blocker in its place

`bug-c-labels-as-values-is-the-whole-of-the-lua-regression` and both lua
regressions are resolved (`6eea46f7c` x86-64, `15e4b9c0a` aarch64, `45a871287`).
Unwired. My scoping on that ticket was **wrong in one respect and I had written
it as fact**: I said it needed "an address-of-label relocation the object writer
does not emit". No relocation was needed anywhere. I took that from frankD's own
cost estimate and repeated it in my own voice without checking — a citation
sourced from a brief, arriving as if measured, which is the failure this repo
has a rule about.

frankD also supplied the control my two counter-tests lacked: **the lua suite
does not discriminate the two interpreter paths** — a `-DLUA_USE_JUMPTABLE=0`
build passes 6/6 as well, so "6/6" was a true sentence about the wrong claim.
The discriminating control is binary identity at the same flags. **That applies
to my five gtk jobs too**: they were failing to COMPILE, so they pass whatever
`__builtin_constant_p` reduces to, and "5/5 GREEN" says nothing about 0 being
the right value. Owed, and being written.

**New blocker, wired:** [[regression-test-core-cfn-return-fnptr-b105]] — a
function RETURNING a function pointer stopped parsing. Three-line repro, bounded
to four probes, and **the auto-filed range is wrong**: it blames `18b3ec2a6`,
while my own optdiff log at `9df0058fe` already shows the file BUILD-FAIL, one
commit after the real cause and two before the blamed sha. Owner frankD.

## `cfn_return_fnptr_b105` closed the same night, and I had the mechanism wrong

frankD fixed it at `2148d95fa` — an uninitialised `paramsOverflow` read, not
the shared-declarator desync I proposed. Unwired. Verified at HEAD, binary
`f28b7828e18d4d5f`, `converged after 2 round(s)`. My four-probe boundary was
real; the reading I put on it was not, and the fifth probe I never ran — the
ZERO-parameter shape, which stayed green throughout — is the one that would
have killed my story on the spot. The attribution half stands and is why the
ticket stays readable rather than deleted.

## The gtk five do NOT discriminate the value, measured — my greens were unqualified

Owed to frankD, whose lua control (a `-DLUA_USE_JUMPTABLE=0` build passes 6/6
too) showed "6/6" was a true sentence about the wrong claim. The same applies to
my five gtk jobs and now it is measured rather than suspected.

Forced `__builtin_constant_p` to reduce to **1** instead of 0, rebuilt the
compiler (`e7376b4065be84f6` → `3e95da5a17bc8878`, so the patch demonstrably
reached it), and ran all five as the Makefile runs them:

| | value 0 | value 1 |
|---|---|---|
| `test_c_gtk` `_call` `_types` `_window` `gtk3_stock` | 5 × rc 0 | 5 × rc 0 |

**All five byte-identical in output** (modulo pid and clock in glib's own
CRITICAL lines). They were failing to COMPILE before the builtin existed, so
they prove it is RECOGNISED — and that is the whole of what they prove. They
say nothing about 0 being the right reduction. **"5/5 GREEN" was correct and
about the wrong claim**, exactly as frankD warned.

**Written a test that does discriminate:** `test/c_builtin_constant_p.c`, wired
into `test-core`. Six rows: the value for a literal (where gcc says 1 and we
say 0 — a deliberate divergence, and a gcc_diff_probe differs there BY DESIGN),
the value for a runtime operand, the operand being UNEVALUATED, soundness of
both arms, use in a constant-expression context, and the load-bearing one —
that `if (__builtin_constant_p(x) && c)` makes its arm DISAPPEAR, asserted
through a symbol declared and defined nowhere, which is the busybox
`data_extract_to_command` shape.

Its **positive control is measured, not assumed**: with the reduction forced to
1 the test goes rc 127, `symbol lookup error: undefined symbol: never_linked`.
Note the failure mode, because it is not the obvious one — **pxx does not refuse
the link.** It warns that the symbol will come from the system C library, emits
a binary, and the loader kills it at run time. A guard waiting for a link error
here would never fire.

## A note on the binary sha, since I quoted the other one all evening

Reverting the experiment and rebuilding reached `101b681ef373eb76`, not the
`e7376b4065be84f6` I started from — the documented case: each rebuild seeds from
the previous local binary, so a revert→rebuild walks off the chain and lands on
a DIFFERENT valid fixedpoint. Both self-reproduce; neither is a miscompile.
Reseeding from `stable_linux_amd64/default/pinned` and touching the sources
converged to `101b681ef373eb76` as well **in 2 rounds** — so that, not the sha I
had been quoting, is this tree's pin-derived fixedpoint, and `e7376b4065be84f6`
was the off-chain one I had accumulated. Every number above `2148d95fa` is at
`f28b7828e18d4d5f`, reached from the pin.

## THE AUTHORITATIVE RED SET — seven's full tier at `0f4d2c907d54`, 16 jobs, 5 causes

Everything before this section was worked off auto-filed stubs and per-job
callbacks. This is the manifest itself, out of `runs-seven.ndjson`
(2026-09-02T01:24:18Z, wall 604.7s): **`new_red` 0, `still_red` 16, `fixed` 1,
`unreached` 0, `timed_out` false, `skip_holes` 1 (`test-core#991`).**

Read the manifest, not `--status`'s "why" block. That block is the **v399 pin
verify at `86c71828cd1e`, 80 commits behind master**, and its own line says 18
of its 19 new reds pass in the full run three hours later. I started to reason
about `00184.c(output)` from it and it is not in the full run's red set at all.

All measurements below at binary `135bb8fec65f1271`, commit `2cf53df52`,
reseeded from `stable_linux_amd64/default/pinned` (`converged after 2
round(s)`), `gate.sh quick` GREEN.

### Group 1 — TEN of the sixteen are one bug, and it is already fixed

Every one of these carries the same stored reason: **`error: C function
definition: more than 16 parameters not supported (MAX_PROC_PARAMS)`** — the
uninitialised `paramsOverflow` read frankD fixed at `2148d95fa`.

| jobs | the program | shape |
|---|---|---|
| `test-c-conformance{,-aarch64,-arm32,-i386,-riscv32}#shard3/6` | `00124.c` | `int (*f1(int a, int b))(int c, int b)` |
| `test-sqlite-threads-{x86_64,i386,aarch64,arm32}#src:tools/compiler_srchash.sh` | `sqlite3.c:53552` | `static void (*memdbDlSym(sqlite3_vfs *, void *, const char *))(void)` |
| `test-core#src:test/cfn_return_fnptr_b105.c` | the test written for `sqlite3OsDlSym` | same |

**A function returning a function pointer.** The conformance corpus, sqlite's
VFS and our own regression test are three independent witnesses to one
declarator, and one initialiser fixed all ten.

Measured green here, all of it: `00124.c` compiles on native + i386 + aarch64 +
arm32 + riscv32; shard 3/6 is **37 pass, 0 fail, 0 skip** on all five targets
(same denominator seven reported, so it is the same 37 programs);
`test-sqlite-threads` **PASSes on all four arches**. `test-core#cfn_return_...`
the watcher already auto-closed at `588d8512f101`.

That is 10 of 16 gone on one commit, and it is why "report by group" is the
instruction — held one at a time, these look like a conformance problem, a
sqlite problem and a C-frontend problem.

### Group 2 — `lib_synapse` × 3: fixed in the compiler, waiting on a pin

`ASTCharArrayCap` answering only for `AN_IDENT` (`9c6b216aa`). These build with
`$(PXX_STABLE)`, so they stay red until the owner pins. **Not my work and not
anyone's**; deliberately still wired.

### Group 3 — `test-lua-cross`: NOT a variadic-ABI gap, and its ticket said it was

`target {i386,arm32,riscv32}: labeladdr`. The ticket
[[feature-c-labels-as-values-on-i386-arm32-riscv32]] was filed at prio 30 saying
the other three targets "already build-fail on their variadic ABI" and that
"nothing measured is blocked on this". Measured: build the same runner with
`-DLUA_USE_JUMPTABLE=0` and **all three build and pass 6/6 under qemu**. So
`IR_LABELADDR` is the whole distance to green, and it blocks a full-tier job.
Prio 30 → 60, summary corrected, wired here. The Makefile's own comment said the
three were "omitted rather than reported as failures" — they are in
`LUA_CROSS_TARGETS` and they are reported; fixed in the same commit.

(That 6/6 is evidence about the REST of the port and not about the jump-table
interpreter, which is the build it excludes — frankD's control, applied to my
own claim before someone else has to.)

### Group 4 — `lib-test#src:tools/crtl_reachability.py`: FIXED HERE

`<unistd.h>` declares `syscall()`; the definition sat in
`lib/crtl/src/sys/syscall.c`. crtl pulls `src/<x>.c` when `<x.h>` completes, so
a program including only `<unistd.h>` — the only header that declares it, and
where every libc declares it — reached the declaration and never the
definition, and **silently imported the symbol from the system C library, ABI
unchecked**. Moved into `lib/crtl/src/unistd.c`, deleted the orphan, and pointed
`<sys/syscall.h>` (numbers only, no sibling `.c`) at where it lives.

Positive control both ways: with the fix stashed, the lint exits 1 **and** a
probe including only `<unistd.h>` warns that it will import from the system C
library; with it applied, the lint is `OK -- 71 headers, 42 modules, every
declared function reachable from its own header` and the probe links to ours and
returns 42. The busybox shape (`<unistd.h>` + `<sys/syscall.h>`, `SYS_getpid`)
also returns 42.

### Group 5 — `tools-devtest#00`: Track T's own tooling, 4 failing checks

Not touched. T owns the tool; four of its `twatch_*_devtest.py` self-checks fail
on the harness's own text. Left for T.

### Where that leaves the goal

Of the 16: **10 fixed and verified, 1 fixed here, 3 waiting on a pin, 1 needs a
backend feature (now ranked and wired), 1 is T's own tooling.** Nothing in the
set is an unexplained compiler defect any more.

`opt` is a DISJOINT tier and its five red shards are not in this manifest; I
measured all six green here at pass=952 skip=144 diff=0 and seven has not re-run
`opt` since 2026-09-01T10:08Z.

### A caveat on the sha I quoted earlier tonight

The conformance and sqlite runs above were FIRST measured at
`f28b7828e18d4d5f`, which `gate.sh quick` then judged not to be the pin-derived
fixedpoint (`the fixedpoint reached from PINNED differs from
compiler/pascal26`). I reseeded and re-measured the decisive parts at
`135bb8fec65f1271`, which gates GREEN — `00124.c` on all five targets and
`test-sqlite-threads x86_64`. The four cross-conformance SHARD runs (aarch64,
arm32, i386, riscv32, ~40 min of qemu) were not repeated and are quoted at
`f28b7828e18d4d5f`; the compile of the one program that was failing was.

I also formed and **refuted** a tidy explanation for the two binaries: that my
first reseed touched `compiler/*.inc compiler/*.pas lib/rtl/*.pas` while
`$(COMPILER_INC)` also covers `compiler/builtin/*.pas` and `lib/asmcore/*.pas`.
Re-running both touch sets from the pin now gives `135bb8fec65f1271` either way,
so the touch set is not the variable and I do not know what was. Recording it
unexplained rather than shipping the neat version.

## Groups 3 and 5 closed; the manifest is down to the three that need a pin

**Group 3 — `test-lua-cross` is GREEN, 24/24.** frankD implemented
`IR_LABELADDR`/`IR_JUMP_INDIRECT` on i386, arm32 and riscv32 (`1f4003e56`) the
same night I re-ranked it, and closed the residual I had flagged rather than
leaving my 6/6 standing unqualified: on i386 and riscv32 the DEFAULT build is
byte-identical to `-DLUA_USE_JUMPTABLE=1` and differs from `=0`, so the binary
passing 6/6 is the jump-table binary and the `=0` row is only the control that
the flag reaches the code. Verified here: 24 PASS, 0 FAIL, 0 SKIP, binary
`5df66928aa3979df` — the same sha frankD reports, which is the first time two
checkouts have independently reached one pin-derived fixedpoint tonight.
Unwired.

**Group 5 — `tools-devtest#00` is GREEN, 133 guards, 0 red.** It was 5 red here
(seven's stored reason named a different, truncated set — this job's red set
moves, because several of its guards are environment- or corpus-dependent).
Four were real defects and one was a guard lying about itself:

- **`sync_contention` was RIGHT and `tools/sync.sh` was wrong.**
  `_ms = _t*500 + _r % (_t*1000 + 1)` closes an interval the comment three
  lines above promises is half-open, so one draw in 1001 lands on exactly
  `3*tries/2` and the guard's own stated bound fails. At 200 draws per check
  that is **~19% of runs red for no cause** — a flake that looks like nothing.
  Dropped the `+ 1`; 20000 draws now give min 0.500, max 1.499, mean 1.0021,
  exactly 1000 distinct values. Positive control: the old formula produced 29
  breaches in 20000. The mean is unchanged, so no patience is traded.
- **`testmgr_hardcoded_tmp`: seven runtime `/tmp` literals across six test
  sources** (five C crtl tests and one Pascal). A path written at RUNTIME is
  one no Makefile sweep reaches, so two concurrent runs share the file. All now
  read `TESTMGR_TMP`, then `TESTTMP`, then `/tmp`. Positive control on every
  one: point `TESTMGR_TMP` at a directory that does not exist and each output
  changes, while the pre-fix binaries ignore it — so the env path is live and
  not a comment. Output byte-identical to before with the variable unset.
- **`npy_cross_target_expectation`: two sources compiled to one binary path**
  (the whole-dynarray-to-var-parameter test and the var-dynarray-parameter test
  both wrote `test_dynarray_var_param26`), so the loser's assertion runs the
  winner's program. Renamed.
- **`exit_observable`: the ratchet tripped and I did NOT re-arm it upward.**
  The corpus grew 665 to 698 and all 33 new differential rows were uncapped, so
  the stdout-only share went 93.083% to 93.419%. Capped five arm32 leak rows
  instead (each already comparing qemu against the x86-64 build of the same
  source), taking it to 647/698 = 92.693%, and re-armed DOWNWARD so the
  improvement cannot be given back. Re-arming upward on a red would have made
  it the third kind of dead guard: one that ratifies whatever it finds.
- **`job_reason` was passing for the wrong reason.** Its scrub check fed a
  literal `/tmp/testmgr-scratch-99123`, which is only what testmgr derives when
  `TESTTMP` is unset — and `Makefile:90` EXPORTS it. So the guard passed by hand
  and failed under the make target, the only way the job actually runs. Its
  input came from a population the real environment never produces. Now derived
  from `testmgr.TESTTMP`, and given the positive control it never had: a path
  outside the scratch root that must SURVIVE, so the assertion cannot be
  satisfied by a scrubber that empties everything.

### What is left

`still_red` at `0f4d2c907d54` was 16. Thirteen are now green and verified here.
The remaining **three are all `lib_synapse`**, they are fixed in the compiler
(`9c6b216aa`), and they build with `$(PXX_STABLE)` — so **nothing but a pin can
turn them green, and a pin is the owner's alone.** No compiler defect is
outstanding in the set.

## Second reading of the manifest: 16 -> 10, and the conformance slot changed OCCUPANT

Two more full runs on seven since (`c43f10db8090` 05:56Z, `9031c8cb7bc3`
06:24Z), both `new_red` 0, both `still_red` **10**. So the thirteen really did
clear, confirmed from outside rather than by my own runs.

**But the conformance reds moved shard3 -> shard2, and that is a different bug
in the same slot, not the set shrinking further.** Those two facts read
identically on a dashboard, which is why the manifest has to be read by JOB and
by REASON, not by count.

I also read the wrong instrument again and caught it: I had 65 commits of drift
when I resumed, and my closing "no compiler defect is outstanding in the set"
was true of a manifest read 65 commits earlier — **a snapshot with an expiry
date, not a state.**

### `00213.c` — OUT OF SCOPE, and the diagnosis is banked elsewhere

**Scope correction from the owner, relayed 2026-09-02: this umbrella is OLD REDS
ONLY.** A red that arrives from another agent's work is fixed by whoever is
working that area, through the normal queue. `00213.c` postdates the set I was
given, so it was never mine — I had already fixed it (`0ee41312d`) before the
correction reached me, and it is green, but the umbrella does not claim it. The
full diagnosis lives in
[[regression-test-c-conformance-shard2-6-2]] so it survives a session restart.
Summary only, below, because the shard3 -> shard2 movement is the part a
dashboard hides and the umbrella is where someone would look for it.

`invalid IR conditional jump target (label not defined)` on all five
conformance targets. The dead-arm prune (`b8ee49996`) drops a constant-false
`if`/`while` body, and its escape guard `ASTSubtreeHasLabel` enumerated
`AN_LABEL` / `AN_LABELADDR` / `AN_GOTO_INDIRECT` while missing `AN_CASE` /
`AN_DEFAULT`. A `case` inside `if (0)` went with the arm; `AN_SWITCH`'s
dispatch, which is outside the arm, still jumped to its label.

**The boundary is the PRUNING, not the nesting** — measured: a top-level
`case`, a `case` in a bare block and a `case` inside `if (1)` all build;
`if (0)` and `while (0)` do not, at every `-O` level including `-O0`, which is
correct because the prune is shared lowering rather than an optimisation.
Fixed at `0ee41312d` with `test/c_dead_arm_holds_a_case_label.c`, positive
control both ways (does not compile pre-fix; a dead arm with no label is still
pruned). Shard 2/6 green on all five targets.

**Corroborated independently the same day:** frankC hit the identical omission
from a second, unrelated pass — pruning statements behind an unconditional
transfer, wired into the `AN_BLOCK` walk — where it made the compiler reject
its own crtl (`lib/crtl/src/stdio.c`, near `vsnprintf`). Two passes, one missing
enumeration, same day. My "a guard that enumerates spellings will keep missing
the next one" was written as a prediction; frankC's instance makes it a
measurement. The reachability decision now lives in one function,
`ASTSeqTailUnreachable`, called by both walks.

### `crtl_names.inc` was 89 functions stale, and that is why my syscall fix did not clear its job

`lib-test#src:tools/crtl_reachability.py` was red for a reason the job's name
does not mention. `crtl-reachability` prints `OK -- 72 headers, 44 modules` in
that job's own log, so my `c64176e26` fix demonstrably took; the recipe dies
four lines later on `crtl-map: compiler/crtl_names.inc is STALE`. The generated
map held **409 functions / 32 headers** against the **498 / 41** the sources
declare — drift since roughly `91b92d5e8c99c3`, most of it the busybox crtl
surface. Regenerated.

That is a behaviour change and not a cosmetic one: those 89 names now resolve to
crtl instead of being imported from the system C library in a libc-free build.
So this one did not lean on `quick` — `test-core` ran behind
`PXX_ALLOW_FULL_SUITE=1`.

**And its residual is NOT mine.** With the map fixed, `lib-test` runs much
further and then dies on
`stable_linux_amd64/default/pinned ... test/lib_synapse.pas` with
`cannot assign ShortString to Char` — the `ASTCharArrayCap` bug fixed at
`9c6b216aa` and still live in the PIN. So `lib-test` as a whole stays red until
the owner pins, exactly like the three `lib_synapse` jobs.

### `tools-devtest#00`: an exculpation with a named owner

Green here at 133 guards, still red on seven on a **different four**
(`twatch_timeout_staleness`, `twatch_timeout_verdict`, `twatch_verify_request`,
`verify_assertions`) — all of which pass here in the same invocation that
showed me my five. "Not the five I fixed" is half a finding. The residual is
**Track T's**: all four are watcher/verifier guards and the difference is
something about that host. Recorded on
[[chore-t-tools-devtest-is-one-job-that-runs-86-guards]] rather than left to
look absorbed by my five. I did not diagnose it and am not guessing.

### Standing

Of the 10: **five were `00213.c` and are fixed; one was the stale crtl map and
is fixed; three are `lib_synapse`, pin-blocked; one is `tools-devtest#00`, whose
remaining four are T's on T's host.** `lib-test` is a fourth pin-blocked job
hiding behind a reachability name.

## Scope, restated, and the honest standing

The owner has narrowed this umbrella to **old reds only** — the set as it stood
when it was written. That removes `00213.c` (five conformance jobs, fixed
anyway at `0ee41312d`, banked in its own ticket) and it removes anything else
that arrives from another agent's work from here on.

What is left of the ORIGINAL set, and who can act on it:

| job(s) | state | who |
|---|---|---|
| `lib_synapse` ×3 | fixed in the compiler at `9c6b216aa`, built with `$(PXX_STABLE)` | **only a pin** — the owner's |
| `lib-test#src:tools/crtl_reachability.py` | stale `crtl_names.inc` FIXED here; the recipe then dies further on at `lib_synapse` under the PIN | **only a pin**, for the residual |
| `tools-devtest#00` | 133 green here; red on seven on a different four watcher guards | **Track T**, on T's host — recorded on [[chore-t-tools-devtest-is-one-job-that-runs-86-guards]] |
| `test_exception_unhandled`, `test_setlen_in_parallel_for_body` | measured FLAKES (10/11 and 10/10 markers) | Track T owns the residual |

**So the honest state is: this umbrella has no outstanding compiler defect that
I can act on. It is blocked on a pin.** Three jobs and the residual of a fourth
need one, and a pin is the owner's alone. That is a complete answer, not a
gap — and per the brief, the green full run is evidence that arrives, not work
I perform.

### Held work, in case this session is restarted

`compiler/crtl_names.inc` is regenerated in the working tree and **not yet
pushed**. `gate.sh quick` is GREEN on it; `make test-core` behind
`PXX_ALLOW_FULL_SUITE=1` was still running when this was written, and it is the
gate that matters because the change moves 89 names from "imported from the
system C library" to "resolved from crtl" in a libc-free build.

If a restart takes it, it is one command to redo and needs no context:

```
python3 tools/gen_crtl_map.py     # 409/32 headers -> 498/41
make compiler/pascal26            # crtl_names.inc is a COMPILER_INC input
```

and then gate. The reason it matters is above: it is the FIRST structural check
in `lib-test`, so while it is stale that whole job dies four lines in and
`lib-test#src:tools/crtl_reachability.py` stays red for a reason its own name
does not mention.

## `lib-test#crtl_reachability` — the exculpation now has an answer, and it is not ours

2026-09-02, frankZ. Binary `9b8ef1068ec8347d925a7ef632286d2a8019bd74cd1d447f651afa78ff9edb9d`,
commit `678fbc3b1`, `converged after 1 round(s)`, `gate.sh quick` GREEN with the
FPC seed canary LIVE.

The half-finding on record was: `crtl_reachability.py` prints
`OK -- 72 headers, 44 modules` **in its own log** while the job goes red later
in the `lib-test` recipe. Nobody owned "then what?". Here it is.

**The job name is its FIRST source file, and the failure is 40 steps down.**
`lib-test#src:tools/crtl_reachability.py` names step 1 of a recipe whose stored
reason ends `cfileops: identical to gcc | ... | cchown: identical to gcc |
pascal26:18: error: stray token at top level (not a declaration): 'clock_t'`.
Read against the Makefile, the step after `cchown` is `$(PXX_STABLE)
test/ctimes.c`, and `ctimes.c` includes `<sys/times.h>`.

**`lib/crtl/include/sys/times.h` did not exist until `f9e495823`.** Before it,
that include fell through to the host's `/usr/include` — the same fallthrough
the job's *other* stored reason warns about in as many words (*"#include
<dirent.h> resolved from the host system (/usr/include), not pxx's own
headers"*). glibc's `sys/times.h` then hits pxx's C parser at line 18 with a
`clock_t` it has no typedef for, and `stray token at top level` is what that
correctly says.

Dates settle it: the watcher's bad sha `5d983997a05a` is **2026-09-01
19:31:36Z**; `f9e495823` is **19:45:39Z**. Both ancestors of origin/master
(`merge-base --is-ancestor`, not `cat-file -e`). **The red was fixed fourteen
minutes after the run that reported it.**

Verified at the bad sha rather than argued: `git archive 5d983997a05a` of
`lib/crtl`, `compiler/crtl_names.inc` and both guard scripts into a scratch
tree, then run them there — `crtl-map: OK -- 397 crtl functions mapped to 28
headers`, reachability OK. **Both guards were green at the bad sha**, so
neither was the cause, which is what makes the `ctimes.c` step the only
candidate left standing rather than the most appealing one.

**The residual, and its owner: Track T's, and it is the INSTRUMENT.** twatch
still lists this as `open regression ... bad=5d983997a05a (2 in range)` with
its own note that *"bad touches NO buildable file"* — an idle bisect that
cannot converge because every commit in its range is docs. All seven
`regression-lib-test-crtl-reachability*` tickets are in `done/`. Nothing here
needs a fix; the watcher needs to re-run the job at a sha past `f9e495823`, or
the stuck-bisect state needs clearing. Named for T, not left implied.

## A red that had not been reported yet — the crtl name map

Same session, `678fbc3b1`. `python3 tools/gen_crtl_map.py --check` is **step 2
of the same `lib-test` recipe**, and it was **FAILING on origin/master** (rc=1)
when this session started: `409 functions across 32 headers` in the generated
map against `498 across 41` in `lib/crtl`.

Green at the bad sha (397/28, measured above) and red now, so this is drift
that arrived AFTER the last regeneration (`d82949bc9`) — the busybox crtl
campaign, thirteen commits, `d71642873` / `e2068a9cc` / `99854e01a` /
`032a55a3f` / `1799aad1a` chief among them, each adding crtl bodies without
regenerating the map that makes them reachable.

**Not found by triage and not reported by anyone** — it was sitting in this
session's working tree as an unexplained modified file after a restart, and the
file's own header says how to interrogate it.

What it actually changes, measured in both directions rather than asserted:
`endmntent()` called with no `#include` is **rejected** by the pinned compiler
(`error: call to undeclared function`) and compiles and links against crtl on
the live one; `alarm()` with no `#include` was already reachable another way
and both compilers emit byte-identical programs (code=306968B). Per-function,
not blanket — the map only matters where nothing else already reaches.

This one is closed, on every host, without a pin: both guards are pure Python
over the tree.

## Correction, same day: `crtl_reachability` is not a fourth blocker — it IS the synapse group

2026-09-02, frankZ, after Track T re-ran the job at `8dcf6ae13` as asked. **My
previous section closed this too early.** The `clock_t` diagnosis above is
confirmed by T independently and stands, but "the fix landed 14 minutes later,
so re-run it" was only true of the SECOND cause. The job is red at HEAD for a
**third** one, and re-running does not clear it.

```
testmgr: RED
pascal26:0: error: incompatible types: cannot assign ShortString to Char
```

That is [[bug-p-a-char-array-through-a-field-or-a-deref-is-not-a-string]] —
`ASTCharArrayCap` answering only for `AN_IDENT`, fixed in this tree at
`9c6b216aa`. It is the construct already written up in the synapse group above.

**Reproduced here independently before accepting it.** Binary
`9b8ef1068ec8347d925a7ef632286d2a8019bd74cd1d447f651afa78ff9edb9d`, origin
`799ac25db`, all three programs, both compilers, same flags:

| program | pinned v399 | HEAD |
|---|---|---|
| `test/lib_synapse.pas` | `cannot assign ShortString to Char` | ok, code=659224B |
| `test/lib_synapse_ssl.pas` | same error | ok, code=720664B |
| `test/lib_synapse_transitive_unit.pas` | same error | ok, code=655128B |

`lib_synapse`'s figures are byte-identical to the ones T measured on seven —
**a second source that fails differently** (different host, different binary,
different harness), which is the only kind that counts.

### The structural half, and it shrinks this umbrella

`lib-test#src:tools/crtl_reachability.py` **is** `lib-test#00`: one job of 198
recipe lines over 39 source files, named for its first source — and the first
line of the `lib-test` recipe is literally `python3 tools/crtl_reachability.py`.
T located the red at **step 83** of it, `$(PXX_STABLE) --mimic-fpc
-Fuexternal/synapse ... test/lib_synapse.pas`.

So the four job names this umbrella has been counting —
`crtl_reachability` plus the three `lib_synapse*` — are **one construct, one
fix, one gate.** Not four blockers. The umbrella's remaining set is therefore:

1. **the synapse construct**, fixed at `9c6b216aa`, waiting on a pin — four job
   names, one cause; and
2. **two that reproduce nowhere** (`test_exception_unhandled`,
   `test_setlen_in_parallel_for_body`).

This is the `tools-devtest#00` lesson arriving a second time from a second job:
**one job name carrying an arbitrary union means the red COUNT is not a count of
causes, in either direction.** There it inflated a fix (five guards closed, the
verdict unmoved); here it inflated the backlog (one construct wearing four
names).

**Corrected 2026-09-04 by frank-coordinator-2c, and the correction is the useful
part.** I first pointed this at
`bug-t-a-job-named-after-its-first-source-file-cannot-name-its-failing-step`
and wrote *"if splitting it is ever ranked"* — that ticket is in `done/`,
resolved 2026-08-30, so it will never be ranked and the pointer would have sent
every later reader to a closed page. **It is also not a regression of that fix.**
That ticket fixed ROUTING (`track:` now comes from the failing step's own
sources) and *structurally refused* to make the slug step-derived, for a reason
that still holds: the slug is both the dedupe key and the close key, and
`close_stub_tickets()` recomputes it from the job when no step is in scope, so a
step-derived slug would leak every stub open silently. It named its own residue
honestly as *"ownership remains unrecoverable"*.

What these two cases are is a **different, unowned residue of that same
deliberate decision** — not "which lane owns this red" but *"how does a reader
tell that four job names are one job, or that one job name is five verdicts?"*
The live ticket is [[chore-t-tools-devtest-00-is-six-reds-with-four-causes]]
(backlog-tools, T, p75, unowned), where both cases are now recorded.

**Why two points argue for rank where one would not:** they point in OPPOSITE
directions from one property. `tools-devtest#00` HID work that was done — an
unmoved verdict standing in front of five closed guards. `lib-test#00` INFLATED
work that did not exist — four names, one construct. A name that over-reports
and a name that under-reports are one ambiguity read twice, and neither
announces itself: an unmoved verdict looks like a live red, and a repeated job
name looks like distinct work.

### The loop worth naming: the shadow is reporting the pin's own defects

T reports seven's pin-shadow lists **exactly three blocking reds, and all three
are `$(PXX_STABLE)` compiles** of a construct this tree fixed. The pin is v399,
cut on the owner's instruction, and independently known broken — it carries
`4af4645ba` without its fix `d5e0a1e48`, which landed an hour after the cut.

So the advisory's blockers are **artefacts of the binary it is advising about**,
and nothing in the tree can retire them: the only thing between here and a clean
advisory is the broken pin. Left to run, that is self-perpetuating.

CLAUDE.md already rules on both halves — *"a red is a reason to pin SOONER, not
later"*, and *"read a shadow verdict as a GRADE, never as permission"* — and
this is the sharpest measured instance of it so far: three reds that exist only
because the pin is old, presented in a field named `would_pin`.

**Recorded, not acted on.** Pinning is the owner's alone, it is irreversible,
and it is explicitly out of this session's brief. A ticket wanting a pin is
never a reason to take one, and a peer's relay is not authority — T says the
same about its own owner. This section exists so that whoever does decide is
looking at a measurement rather than a red count.

## 2026-09-04, frankZ — the newest full tier is TWO reds, and one is now closed

`27303aeeb35c` on seven, 2026-09-04T17:20:00Z, tier `full`, 1167s. `STILL-RED`
lists exactly two jobs. Not thirteen; the brief's starting number is thirteen
days of work behind and every intervening ticket in the old `blocked-by` list
is in `done/`. The list above is replaced with what is actually blocking.

**1. `tools-devtest#00` — CLOSED, `3914444ff`.** Three unrelated causes, none a
compiler bug: an unwired test (`test/c_offsetof_in_a_static_array_initializer.c`
landed with its own fix at `62463923f` and nothing ran it), two files naming
`/tmp` paths at runtime, and `exit_observable_devtest`'s stdout-only ratchet,
which **had never been green in its life** — see
[[bug-t-the-exit-observable-ratchet-was-red-at-its-own-arming-commit]], resolved
in the same push. 134 guards green, was 131 green / 3 RED.

This one mattered beyond its own row: it is the red **inherited into pin v403's
baseline** (`pin_baseline.reds == ['tools-devtest#00']`, carried from v402), so
it was grading every pin taken while it stood.

**2. `test-core#src:test/c_crtl_wait.c` — the tree is exonerated.** riscv32's
rusage row, red on seven and green on plexus from byte-identical compiler bytes.
Isolated to seven's emulator being a Debian generation behind, with the host
kernel eliminated on seven's own box by a probe carrying its own positive
control. [[regression-test-core-c-crtl-wait]] and
[[bug-t-tstate-fingerprints-the-code-and-the-hardware-but-not-the-emulator-toolchain]].

**Where that leaves this umbrella.** Its target is a full run with no RED tier,
and the remaining red **cannot be cleared from the tree** — it needs root on
seven (the owner) or testmgr surgery to skip a row on an absent host
capability (T). So the umbrella is one commit from its goal and the last step
is not a lane's to take. That is worth stating plainly rather than leaving it
to look like unfinished work.

**And the shape of the finding is the reusable part:** two reds, and after
diagnosis *neither was a compiler defect*. One was a guard that could not pass
and one was an emulator version. A red tier does not mean a broken compiler,
and this umbrella's whole history is that reading being made by default.

## 2026-09-05 — the first full tier after seven's dist-upgrade

Full tier `5b5fdb0b32d3`, seven, 2026-09-05T18:33:42Z, verdict RED.
`toolchain: kernel=7.0.0-31-generic gcc=15.2.0 qemu=10.2.1(6 of 6)
wasmtime=48.0.1`, `toolchain_fp: b926fcc528d9`, `compiler_sha256:
fe1e9c37d322…`.

### `c_crtl_wait.c` PASSES, and that is not a demonstration

`test-core#src:test/c_crtl_wait.c` -> **`pass`**. Read out of the run's job map
(4255 entries), NOT inferred from its absence in the red list — a job missing
from a red list has two causes, and this file's own rule is that the two must be
separated rather than collapsed.

**The dist-upgrade moved three things at once**: kernel 6.8.0-138 -> 7.0.0-31,
gcc 13.3.0 -> 15.2.0, qemu 8.2.2 -> 10.2.1. So this is the original
seven-vs-plexus A/B with one MORE variable in it, not one fewer. What can
honestly be said: the `waitid` probe eliminated the kernel on seven's own box
before the upgrade, and the row went green after qemu moved — two measurements
pointing the same way. **That is not a single-variable demonstration and the
residual stays owned.**

### THE NEW-REDS ARE PIN v403, AND v404 LANDED SEVEN MINUTES LATER

Eight-plus `lib-test` and `demos` jobs, every one `unknown type: TMethod`
sourced from `stable_linux_amd64/default/../../lib/rtl/typinfo.pas`. New
source, old pin: `a623307bd` was already in the tier's tree.

**Do not read these as compiler regressions, and do not read them as an
argument that a pin is still needed.** Verified at ref level, twice, by two
sessions:

    5b5fdb0b32d3  2026-09-05 18:10:50Z  the tier's tree
    8844c8c42     2026-09-05 18:17:45Z  chore(stable): pin v404 -- binary
                                        sha256 fe1e9c37d322 -- unblocks 20
                                        lib/rtl units and all of lib/pcl

`8844c8c42` is the ONLY commit touching `stable_linux_amd64/` since that tree,
and `merge-base --is-ancestor 5b5fdb0b32d3 8844c8c42` is true. **The tier is
6m55s stale in the one dimension those reds depend on.** They are the last
measurement taken BEFORE the pin, not a case for it.

**RETIREMENT EVENT: the next full tier after `8844c8c42`.** They should clear
with nobody touching a line. **If they do not, that is a finding** — v404's
recorded binary sha256 is `fe1e9c37d322`, the same binary this tree builds, so
a persisting TMethod red would mean the pin did not do what its own commit
message says.

### `tools-devtest#00` — red there, green here, and the tree is exonerated

The failing member is `tools/devtest_sync_fold.py` (4 checks). `git diff
5b5fdb0b32d3 abd3a468b -- tools/devtest_sync_fold.py tools/sync.sh` is **empty**
— byte-identical. It passes on plexus at a descendant tree.

Same shape as `c_crtl_wait`: the box, not the tree. That devtest drives **git**
25 times — clone, rebase, containment — and seven's git moved in the same
dist-upgrade. **`toolchain_fp` did not include git**, so the field built to
answer exactly this question could not. Now fixed; see the toolchain ticket.

### Reading the transition the callout cannot announce

`TOOLCHAIN FIRST RECORDED` will **never fire for seven**. Its first
post-upgrade report (18:20:49Z) latched the baseline `b926fcc528d9` before the
callout existed (`2bdbe4249`, 18:29:11Z), so every later report correctly finds
`prev == now` and stays silent. Eight minutes.

**So read the transition by hand, and this is where it is written down:**

| | before (measured 2026-09-04) | after (report 18:33:42Z) |
|---|---|---|
| kernel | 6.8.0-138 | 7.0.0-31-generic |
| gcc | 13.3.0 | 15.2.0 |
| qemu (all) | 8.2.2 | 10.2.1 |

The `toolchain:` line is unconditional and spelled out in full, which is what
makes this possible without the callout.

## 2026-09-05, later — the retirement condition FIRED, as stated

Full tier `c1fe3e414d25`, seven, 19:14:28Z, `toolchain_fp b926fcc528d9`.
`merge-base --is-ancestor 8844c8c42 c1fe3e414d25` is true, so this is the first
full tier after pin v404.

**`grep -c TMethod` on the report: 0.** The eight-plus `lib-test`/`demos`
NEW-REDs of the previous tier are gone, with nobody touching a line. The
retirement condition recorded above is met, and the inverse condition — a
persisting TMethod red meaning v404 did not do what its commit message says —
did not fire.

### The class-var group is STILL-RED and that is NOT a harness disagreement

`test-core#src:test/strict_fpc_case_fail.pas` is still red here, while frankH's
run of that target went GREEN end to end (15,253 lines against the blocked
run's 3,783). Those look like two instruments disagreeing. They are not:

    tier tree   c1fe3e414d25   2026-09-05 19:01:13Z
    the fix     8727b1907      2026-09-05 19:14:59Z   (+13m46s)

`merge-base --is-ancestor 8727b1907 c1fe3e414d25` is FALSE. **The tier predates
the fix by thirteen minutes and forty-six seconds.** Its red is a correct
statement about the tree it measured.

### THE PATTERN, three instances in one evening

On a tree moving this fast, **a tier's verdict is a statement about a tree that
is typically minutes old, and every natural reading of it is present tense.**

| the reading | the offset | which way |
|---|---|---|
| NEW-REDs "argue for a pin" | pin v404 landed **6m55s** later | already fixed |
| class-var "disagrees" | the fix landed **13m46s** later | already fixed |
| `TOOLCHAIN FIRST RECORDED` "did not fire" | baseline latched **8m22s** earlier | never could |

In all three the report is correct and the *tense* is what misleads. **Before
reading a tier as a finding, check what landed between its tree and now** —
`git log <tier-sha>..origin/master -- <the files the red depends on>` costs one
command and settles it. Two of these three were caught only because somebody
checked at ref level rather than reasoning from the clock.
