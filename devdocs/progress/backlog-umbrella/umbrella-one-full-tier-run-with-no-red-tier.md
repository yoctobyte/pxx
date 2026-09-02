---
slug: umbrella-one-full-tier-run-with-no-red-tier
track: T
prio: 85
type: umbrella
blocked-by: [regression-lib-test-lib-synapse-3, regression-lib-test-lib-synapse-ssl, regression-lib-test-lib-synapse-transitive-unit, regression-test-core-test-exception-unhandled-3, regression-test-core-test-setlen-in-parallel-for-body-2, bug-c-labels-as-values-is-the-whole-of-the-lua-regression]
created: 2026-09-01
owner: frankZ
summary: "GOAL, not a unit of work: one `full` tier run with no RED in any tier judged at that sha. That is what grades a pin `green` rather than `reds(N)`, and no PINNED sha has earned it since v354 on 2026-08-19. A pin is neither blocked nor gated by this — CLAUDE.md now says a valid pin IS the self-host fixedpoint and nothing else may block one, and rollback falls back to the most recent pin, so recovery is never empty. What a green run buys is a rollback target that is VERIFIED rather than merely recent. The umbrella ENDS when one such run comes back; it is not a standing triage desk."
---

# One full tier run with no RED tier

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

## The groups — state at 2026-09-02, binary b9fd008f89ef, commit cdefc55e1

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
