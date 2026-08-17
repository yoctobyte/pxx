# Track T — offloaded continuous testing (watcher + agentic test manager)

Status: face 1 (watcher) landed 2026-07-07 (`feature-track-t-watcher`);
face 2 (agent) live since 2026-07-07 (`feature-track-t-agent`, in working/).
One-stop launcher `./trackt` + two-phase watcher + learned-metrics scheduler
+ web UI landed 2026-07-08. Design discussion + decisions: user, 2026-07-07/08.

## Why

The full gate (all targets + corpus + conformance + self-host) costs 10+
serial minutes — too slow for a dev inner loop, yet a trivial change can
regress any target. Track T makes testing a PERMANENT BACKGROUND PROCESS:

- Dev tracks confirm **native** health themselves (seconds), push, move on.
- The full matrix runs asynchronously on whatever box is available.
- Regression feedback may arrive minutes later — that's accepted — but it is
  always tied to an **exact git SHA**, so diving back into the offending
  change is one checkout.

## The pieces

| tool | job |
|------|-----|
| `./trackt` (`tools/trackt.py`) | **the one-stop launcher**: status, daemon start/stop/restart, live progress view, manual runs, box setup + git-access check, config, log tail, web UI. Thin frontend over the state files below. |
| `tools/testmgr.py` | adaptive parallel test runner (tiers quick/native/limited/full). Learns per-job metrics on each box (`.testmgr/metrics.json`: duration/RSS/cores EWMA) and schedules by them: measured-mem packing, cores-sum cap, per-job hang timeouts (~10x expected), SLOW flags. Writes `.testmgr/live.json` progress each second (weighted % from expected durations). |
| `tools/twatch.py` | face 1: dumb, reliable watcher daemon. Two-phase: fast verdict at `fast_tier` (default `native`) minutes after a push; full matrix backfills while idle and is aborted+discarded when a testable push arrives. Skips docs/tstate-only commits. Publishes tstate; heartbeats `.testmgr/watch.json`; optional deterministic stub tickets (`autoticket`). |
| `tools/twatch-setup.sh` | box readiness check (+ `--fetch-corpus`). Prints what's missing with apt hints and the start command. |
| `tools/twatch_web.py` | optional read-only Flask UI (spawned by `trackt`): live run, history from `tstate/runs-<host>.ndjson`, regression frequency, report browser. Loopback-only by default. |
| `devdocs/progress/tstate/` | published state: `<host>.json` (rolling state), `runs-<host>.ndjson` (uncapped run archive), `reports/*.md` (only when something CHANGED or RED), `TSTATE.md` (index). |

Config lives in `<clone>/twatch.conf` (JSON; `trackt config` edits it —
tier/fast_tier/interval/debounce/no_bisect/autoticket/web/web_port;
interval/autoticket/no_bisect apply to a running daemon, the rest on restart).

## Deploy a watcher box

```sh
git clone git@github.com:yoctobyte/pxx.git ~/trackt-watch \
  && ~/trackt-watch/trackt setup --fetch-corpus \
  && ~/trackt-watch/trackt start
```
(`trackt setup` also verifies git fetch/push access. Equivalent low-level
one-liner lives in the `twatch-setup.sh` header.)

Notes:
- The box needs an ssh key with **write** access (the watcher pushes tstate).
- No FPC needed: the compiler self-seeds from the committed stable binary.
- Full tier wants `qemu-user` (i386/aarch64/arm/riscv32), `xvfb`, `gcc`;
  without qemu run `--tier limited`. Corpus trees are gitignored — fetch via
  `--fetch-corpus`, else those jobs SKIP (green).
- twatch **refuses a checkout with uncommitted changes** — it does detached
  checkouts of arbitrary SHAs and must never do that under a live dev tree.
  Always give it its own clone. (`--status` is read-only and works anywhere.)
- Several watcher hosts in parallel are fine: reports are host-tagged, pushes
  rebase-retry. testmgr's adaptive scheduler self-tunes to the box, so the
  same command fits a laptop or a Xeon.
- Knobs: `--tier`, `--host`, `--interval`, `--debounce` (repo-quiet window
  before testing a burst), `--once` (cron style), `--no-bisect`.

### Corpus trees: whose job
`library_candidates/` (lua/sqlite/zlib/c-testsuite/tcc/cjson) is gitignored;
absent trees make corpus jobs SKIP (reported green) — silent coverage loss.
- **Non-agentic watcher box:** MANUAL — the user runs
  `tools/install_lib_candidates.sh all` (or `twatch-setup.sh --fetch-corpus`)
  at deploy time and after new corpora land.
- **Agentic Track T:** the agent's duty. On each session it checks its
  watcher clones for missing corpus trees and runs
  `tools/install_lib_candidates.sh all` — SKIPped corpus jobs in tstate are a
  finding to fix, not a green to accept.

## Dev-track protocol ("confirm native, offload the matrix")

After a change (also in CLAUDE.md workflow norms):

1. Always confirm natively yourself: `tools/testmgr.py --tier quick` (+
   self-host fixedpoint for compiler changes). ~40s.
2. `tools/twatch.py --status` — is Track T covering the repo?
   - **exit 0 (UP):** push. Cross targets, corpus, breadth = T's job.
     Regressions come back asynchronously as tstate reports (and, with
     face 2, as tickets) naming your exact SHA.
   - **exit 1 (DOWN/absent):** old rules — run your lane's full gate
     (`--tier full`, or `limited` + the targets you touched) before pushing
     anything risky.
3. Master MAY carry cross-target reds for hours; tstate is the truth. A
   core-job red older than a day is a revert candidate.

### Liveness without pings
`--status` needs no network and no heartbeat: T counts as UP iff every
commit older than a grace window (default 45 min, `--grace`) was tested by
some host. A quiet watcher on a quiet repo is indistinguishable from a dead
one — and it doesn't matter, because there's nothing it should have tested.

## Report contract (sparse by design)

- All-green, nothing changed: only `<host>.json` + the `TSTATE.md` index
  move. One commit line: `tstate(host): <sha> GREEN`.
- Something changed or RED: additionally `reports/<utc>-<sha7>-<host>.md`
  with frontmatter (sha, parent_tested, host, tier, wall, scale, verdict)
  and NEW-RED / FIXED / STILL-RED lists, verbatim first-failure log, and a
  one-line repro (`testmgr --tier <t> --job '<name>'` at `<sha>`).
- Signal only, never log dumps. NEW-RED **vs the previously tested SHA** is
  the signal, not raw fail counts.
- Idle watcher time narrows open regression ranges: midpoint commit, failing
  job only (`testmgr --job`) — lazy bisect toward a single SHA.

## The watcher verifies the PIN, not only HEAD

A pin is fast and unverified **on purpose**: `make stabilize-fast && make pin`
is ~34s and proves the self-host fixedpoint, on the explicit trade that a bad
pin is **recovered, not prevented**
(`task-t-pin-fast-track-t-owns-verification`). Track A pays 34s instead of 25
minutes, and T supplies the verdict afterwards.

That second half was missing, and the gap is invisible unless you go looking
for it. The escalation ladder deepens **HEAD**; a pin is whatever HEAD happened
to be when a human ran `make pin`. By the time the box climbs from the fast
tier to depth, HEAD has moved on and the pin is history — so the pin was only
ever covered *by accident*, when it happened to still be HEAD. Measured
2026-08-11 over `pin.log` x `runs-*.ndjson`:

> **18 of the last 25 pins never received a `full` run. 13 were never judged in
> any tier at all.**

Which is exactly backwards: `pinned` is the ground Tracks B/C/D/E build every
artifact on, and it was the one sha nobody was deepening.

So the watcher now schedules the pin itself, at two priorities:

- **native depth on the pin runs AHEAD of idle depth on HEAD** — that binary is
  what other tracks are compiling against *right now*, while HEAD is a sha
  nobody has adopted;
- **platform breadth on the pin runs after HEAD's ladder** — ordinary work, and
  it is what lets `trackt pinstatus` name a last-fully-green pin to fall back
  to (`pin_is_green` requires a `full` run).

Two properties this must keep, and both are easy to break:

1. **It does not go through `test_sha`.** That function maintains the HEAD
   progression — `last`, the per-job map, the open-regression ledger — all
   defined relative to the sha sequence the host is walking. Feeding it a
   days-old pin sets "last tested" backwards, diffs the pin's jobs against
   HEAD's map and manufactures NEW-RED/FIXED pairs out of nothing but the time
   travel. `verify_pin` publishes exactly one run record and touches nothing
   else.
2. **A box that could not measure publishes nothing.** Same rule as everywhere
   else. An unjudged pin is a known unknown; a fabricated verdict on the
   artifact every track builds against is far worse.

Read the answer with `tools/trackt.py pinstatus` — the `pin.log` x `tstate`
join, and `make revert` demotes.

## Rule: a watcher clone's worktree is HISTORY, not current state

The clone is **detached at the sha under test** for most of every cycle, so its
working tree is a point-in-time snapshot of an older commit:

- newer `tstate/reports/*.md` **do not exist there yet**
- `<host>.json` shows that sha's verdicts, not today's
- file **mtimes** are rewritten by every checkout

Measured 2026-08-02, minutes apart, same clone: the worktree's newest report was
`210523Z-74a9251` with 1 failing job while `origin/master` had
`212028Z-4d61f85` with 0. Four separate bugs in one day came from reading it —
`make` trusting an mtime and testing the *pinned* binary, `--status` reporting a
healthy watcher as DOWN, `--follow` hanging for the agent that just pushed, and
the health observer alerting twice on an already-fixed red. The fourth
reproduced the second a few hours after it was fixed, in a different tool.
**Knowing the rule was not enough; nothing enforced it.**

So, when you want to know what is true NOW:

```python
twatch.materialize_tstate(repo)      # whole tstate subtree out of origin/master
twatch.states_at(repo, "origin/master")   # just the per-host json
twatch.head_detached(repo)           # ...or decide for yourself
```

`tools/tstate_reader_devtest.py` enforces it: a tool that joins a clone path
with the tstate directory must either route through those helpers or be added
to its `ALLOWED` list **with a reason**. The list is short and argued on
purpose — a guard that is muted as noisy is not a guard.

Detaching is not the bug and is not going away: `twatch` checks out arbitrary
shas to test them, which is why it demands its own clone and refuses a dirty
one. The defect is only ever in readers that assume the tree reflects now.

## Diagnostic: which numbers in your reports have NEVER changed?

A constant in a report is the hardest defect to see, because it reads as a
**property of the system** rather than as a wound — and it renders identically
whether the cause is benign or serious.

The worked case. Every `lib-test` verdict from enrolment onward ended:

```
167/167 pass, 2 skip (corpus absent)
```

That line was **true every single time it was quoted**, including in handover
messages. It answered *"how many jobs skipped?"* — while the question that
mattered was *"why has that number never been zero?"* The two skips were the
synapse jobs; synapse was absent because testmgr's own corpus message said it
could not be fetched by script; that message was false the day it was written.

So the loop closed: **the instrument reported the consequence of its own
documentation.** A measurement system with a path back to its own input is a
failure mode a watcher is uniquely exposed to, and nothing in the number could
distinguish "benign" from "two-month coverage hole".

**When the evidence is identical under both readings, the check is in the wrong
place — not merely too weak.** No amount of reading that line harder would have
helped; the question had to be asked of a different thing.

So, periodically, of your own reports:

- which figures here have never moved?
- for each: do I know *why* it is that value, or only *that* it is?
- would I notice if it were a wound rather than a baseline?

Related: the same shape one level down is a true fact about the wrong subject
(below); this is a true *measurement* answering the wrong question.

## Rule: "filed", "done", "already handled" are CLAIMS — and `ls` settles them

Work that exists in prose but not as a rankable ticket is invisible to
`progress.sh next` / `ready`. It is then either rediscovered from scratch or
silently never happens, which is what
`project_decided_tickets_are_invisible_work_and_get_rediscovered` names. Three
instances surfaced on 2026-08-16/17 alone, all in Track T's own area:

| where the claim lived | reality |
| --- | --- |
| `feature-t-uforth-benchmark-harness` listed three follow-ups as *"filed, not blocking"* | none of the three existed anywhere |
| `decided/decide-watcher-lifecycle-manual-only.md` named a slug for the status bug | never filed; nothing scheduled it, so nothing built it |
| `feature-t-uforth-benchmark-harness` itself | **built** 2026-07-22 and left in `backlog/`, so it sat in the ready queue for a month as phantom work |

Note the third is the mirror of the first two: the ticket outlived the work
instead of the work outliving the ticket. Both directions cost the same thing —
the queue stops describing reality.

**The check is one command and it is not optional when the phrase appears:**

```sh
ls devdocs/progress/*/<slug>.md          # does the ticket exist at all?
grep -rl "<slug>" devdocs/progress/      # ...under any name?
```

Treat *filed / done / already handled / tracked separately* in a ticket body as
**unverified** until that returns something. It is the same discipline as
verifying a peer's claim before acting on it, applied to the claims a ticket
makes about itself — and a ticket is the harder case, because prose in a ticket
reads as a record rather than as an assertion.

**When resolving, check the inverse too:** if the body says a follow-up was
filed, file it now or delete the sentence. A resolved ticket that leaves a
phantom follow-up behind converts one invisible item into a permanently
invisible one, since nobody re-reads `done/`.

## Rule: a coverage claim needs its BOUNDARY checked, not just its result

Track T's product is coverage claims — "the tier is green", "this sweep covered
those commits", "that guard handles this case". The characteristic way they fail
is not a wrong result but an unchecked boundary, and it is invisible from the
inside because the work really was done and really did pass.

Two instances on 2026-08-16, from two different agents, and they are mirrors:

- *"the guard would have caught both false attributions"* — it caught one. The
  other commit touched `Makefile` and `test/**`, which the rule deliberately
  keeps in scope.
- *"native GREEN 1278/1278, covering both follow-up commits"* — true at the sha
  it ran at, and a third commit had landed 2.5 minutes before the claim was
  made.

Same error: asserting coverage without checking where it stops. Neither agent
caught it in themselves — in both cases they had done the work and were
reporting it, which is exactly the state in which the boundary goes unexamined.

**The cheap discipline, and it is two seconds:**

1. **Name the sha or scope in the claim.** Not for the record — so a reader can
   falsify it. Naming `5593b04bd8c2` is what let the gap be spotted in seconds.
2. **Then check that boundary is still true when you make the claim.** Naming
   the sha makes the error findable; re-checking `git rev-parse HEAD
   origin/master` makes it not happen.

A green verdict is a statement about a tree, and the tree moves. So does the
set of cases a rule covers.

### The same shape one level down: a true fact about the wrong subject

Related and worth reading together, because double-checking cannot reach it —
re-reading the condition CONFIRMS it, since it is true:

- `pgrep -f "systemctl --user restart trackt"` matched a process. It was the
  waiter's own command line, not a restart. (The fix: read `ActiveEnterTimestamp`
  — **state, not evidence-of-state**.)
- A record-constant parser arm keyed on `tkString` because a single-char literal
  *is* that token — but only the destination field type can decide whether `'Z'`
  is a string or an ordinal.
- A pin-built job is immune to `compiler/**` — true, and not sufficient, if the
  commit also touched the `Makefile`.

Every one is a checkable, correct statement standing in for the deciding one.
Scrutinising the condition harder does not help; asking *what would distinguish
the two readings* does.

## Triage rule: a converged bisect range is not always an accusation

The watcher narrows an open regression to one commit and prints it. That number
reads as a culprit, and four times out of five it is. The other cases cost real
time on 2026-08-16 — two agents, several messages each — so they are written
down here with the guard that now handles each.

| the bisect result is | because | guard |
| --- | --- | --- |
| a **real** first failure | the ordinary case | none needed |
| an **innocent** commit | the signal was a TIMEOUT **and the expensive step exists across the whole range**, so the search converges on whichever commit straddled the budget | `bisect_step` refuses to bisect a `timeout` — see the caveat below, this is currently too broad |
| a commit that **cannot** be causal | the job builds only with `$(PXX_STABLE)` and the commit moved no pinned binary — the bytes that compiled it did not change | `pin_immune()`; testmgr publishes `pin_built` per job |
| a **correct** commit that is not a fault | a feature retired a recorded divergence and its expectation was left behind — the range is *right*, the commit is not a defect | not decidable; the stub flags a REFUSAL expectation and asks the reader to check |

**Caveat, 2026-08-18: the timeout guard is too broad, and a real case proved
it.** "A timeout is a duration signal, therefore not bisectable" is wrong as
stated. Two shapes:

- `crtl_exp2` — every commit in the range already runs the job, and the budget is
  straddled somewhere in the middle. The landing is wherever load tipped it:
  **arbitrary**, and refusing is right.
- `callbacks.npy` — the range SPANS the commit where the job *started* doing the
  expensive thing (`5215148bb` added the Makefile lines that first EXECUTE three
  tk tests, bringing `timeout 120 xvfb-run` with them). The landing is
  **exact**, and refusing would have suppressed a correct result.

That bisect only ran because the inner `timeout` was invisible to testmgr, so it
was recorded as `fail`
([[bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic]]).
**Fixing that ticket will start refusing bisects like it** unless the guard
learns the distinction — the discriminator being whether the accused commit
introduced or enlarged the job's work, in the spirit of `pin_immune`.

Recorded rather than fixed here because the two changes belong in one commit.

The three guards sit in descending order of confidence, and it is worth keeping
them distinguishable rather than blurring them into "the watcher is unsure":

1. **Decidable** — pin provenance. Arithmetic, not judgement. If the compiler
   bytes did not move, the commit cannot have changed the output.
2. **A judgement about signal kind** — a timeout is a duration, and durations
   are not functions of the tree alone.
3. **Undecidable, and says so** — a refusal expectation (`ValueError`,
   `{%FAIL}`, a `*_fail` test) changes meaning when a feature lands. Only a
   human reading the expectation can tell "the answer changed because we fixed
   something" from "because we broke something". The stub flags it and declines
   to rule.

**Do not loosen the pin-provenance prefix list.** It exonerates only when EVERY
changed path is under `compiler/`, `tools/`, `devdocs/` or `docs/`. A commit
that also touches `Makefile`, `lib/**`, `test/**` or `examples/**` stays in
scope, because a pin-built job reads those. The costs are asymmetric: a wrong
exoneration hides a real regression silently, a missed one costs one message —
and this rule runs unattended.

**A fifth case exists and is deliberately unhandled: a FLAPPING job**, red and
green at the same tree. It shares the timeout case's consequence (the commit is
arbitrary) but not its cause. Not automated, because both observed instances
were on a box simultaneously running a dev session's compiles and the watcher
itself — so the property is "flaps under contention", and a harness that is part
of the contention cannot measure it. One loaded day is a sample of one.

## Triage rule: green on dev, red on the watcher ⇒ suspect HOST COUPLING first

The boxes run different distros on purpose (dev Ubuntu 24.04, `xeon` 26.04,
the planned rPis Raspberry Pi OS). Different distro ⇒ different system
libraries, different glibc, different system CPython. A test whose expectation
is coupled to any of those is green where it was written and red forever
everywhere else — and it looks *exactly* like a watcher fault, which is why it
survives triage. One instance cost three wrong diagnoses (twice written off as
a phantom) before the distro difference was guessed:
`test_nilpy_import_sqlite` asserted `= "3045001"`, i.e. sqlite **3.45.1**, the
authoring box's version. Fixed by asserting the SHAPE (any well-formed
`3.x.y`), which is what the test exists to prove.

**Read the log tail first, and read the compile line.** If it says `ok:`, the
build succeeded and the failure is the OUTPUT COMPARISON — so the question is
what the expected value depends on, never what the compiler did. In the sqlite
case that `ok:` was in every report and was walked past each time.

**The oracle is `ldd`, not the shape of the number.** A test is host-coupled
when it reaches OUTSIDE the repo at runtime — a system shared library, a host
binary, host data. That is checkable in one command, and it beats guessing from
what an assertion *looks* like. The 2026-08-03 audit of the two families
flagged as residual risks found both to be false alarms, for exactly this
reason:

- **Suspected allocator/RSS assertions** (`= "640000"`, `= "396000"`,
  `= "770000"`). Not allocator numbers at all: 396000 and 770000 are the
  compiled program's own arithmetic (180 and 350 statements x 2200), and
  640000 is a raise count the program prints. Measured on xeon/26.04: 396000,
  770000, 640000 — exact. The one real memory assertion beside them is already
  a tolerance band (`RSS > 90000` KB, measured 75308 here) and is already gated
  on `[ -x /usr/bin/time ]`.
- **cpyext vs the host CPython** (`test_cpyext_markupsafe.npy` and siblings).
  No host CPython is involved: the tests compile vendored, unmodified
  extension sources against **pxx's own** `lib/cpyext/include/Python.h` and
  runtime, with `Py_LIMITED_API` pinned in the recipe. `ldd` on the built test
  reports *not a dynamic executable* — it links nothing at all, let alone
  libpython. Contrast the sqlite test, which genuinely links
  `libsqlite3.so.0`: that is what host coupling looks like.

So the rule is: **shape-based or tolerant when the value comes from outside the
repo; exact when the program computes it itself.** A dependency that may be
absent gets an explicit guard instead — the Tk test's `command -v xvfb-run`
plus `[ -e ... ]` is the pattern to copy, and an unfetched corpus tree is the
same idea done by testmgr.

Each individual test fix belongs to the lane that owns the test (the sqlite one
was Track N); T owns this rule and the audit, not other lanes' tests.

## Face 2 — the Track T agent (backlog)

A Claude agent, supervised session or cron, that consumes tstate and adds
judgment: files/updates deduped regression tickets (one per failing-job
signature, repro + commit range), drives bisects instead of waiting for
idle, escalates day-old core reds with a revert proposal.

**Self-directed (user decision):** the T agent OWNS the Track T sources —
free to improve/refactor/optimize testmgr/twatch/report format/tiers on its
own initiative, no ticket or approval needed. Its gate: `testmgr --tier
full` green; and it tests the *tooling itself* with quick tiers against a
scratch bare repo (fake central), never with long runs. Watcher identity
writes only `tstate/**`; the agent identity may touch tickets like any
track agent — that's the deliberate difference between the faces.

## Testing the tooling (how face 1 was verified, repeatable)

```sh
S=/tmp/scratch; git clone --bare . $S/central.git          # fake central
tools/twatch.py --clone $S/wc --remote $S/central.git --tier quick --once
# break a test in a third clone, push, --once again -> RED report w/ exact SHA
# revert, --once again -> FIXED, regression closed
```
Quick tier only (~4s a run); never validate infra with full-tier runs.
