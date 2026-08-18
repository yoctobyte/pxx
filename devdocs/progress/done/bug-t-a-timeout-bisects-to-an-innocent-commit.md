---
track: T
prio: 45
type: bug
blocked-by: []
summary: "`lib-test#src:test/crtl_exp2.c` has been STILL-RED since 096da361dd93 with a `(timeout)` verdict, and the bisect named that commit — which touches nothing the job builds (the job uses the PINNED compiler; the commit's Makefile lines went to test-core). Every step of the job runs clean standalone in seconds. A timeout is a DURATION signal, so bisecting it converges on whichever commit happened to straddle the budget, and the report presents that with the same confidence as a real first-failure."
status: done
---

> ## ⚠ THE RULE IN THIS TICKET WAS NARROWED — read this first
>
> This ticket states, and its fix encodes, *"a timeout is a duration signal, so
> bisecting it is not sound."* **That is too broad**, and it is the form a
> searcher finds first, because this is the ticket that comes up for "timeout
> bisect". It has already nearly caused one wrong dismissal (2026-08-18).
>
> The narrowed rule:
>
> | when | landing | refuse the bisect? |
> | --- | --- | --- |
> | the expensive step exists across the **whole** range | arbitrary — wherever load tipped it | **yes** (this ticket's case, `crtl_exp2`) |
> | the range **spans** the commit that first made the step execute | **exact** | **no** — refusing suppresses a correct result |
>
> Counter-example: `callbacks.npy` bisected to `5215148bb`, the commit that first
> made three tk tests *execute* under `timeout 120 xvfb-run`. Converged, exact,
> and correct. It only ran because the inner timeout was invisible to testmgr and
> was recorded as `fail` rather than `timeout` — so `bisect_step`'s refusal never
> fired.
>
> **Consequence:** fixing
> [[bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic]]
> will start refusing bisects like that one unless the guard learns the
> distinction. The two changes belong in one commit. Full table in
> `devdocs/dev/track-t.md`.


# A timeout bisects to an innocent commit, and the report does not say so

Filed 2026-08-16 by the Track A+P session, from the monitor stream. **Not fixing
it — Track T owns the tool.** Filed because the bisect result is currently
pointing at a Track A commit, and the next person to look will go hunting a
compiler regression that is not there.

## What the report says

```
## STILL-RED
- lib-test#src:test/crtl_exp2.c — test/crtl_exp2.c examples/tk/hello.npy +5

## first failure: lib-test#src:test/crtl_exp2.c … (timeout)
repro: tools/testmgr.py --tier full --job 'lib-test#src:test/crtl_exp2.c'
```
```
ok: …/crtl_exp2  [code=228732B …]
  tk-nilpy: ok
```

and `TSTATE.md`: *bad `096da361dd93`, last good `45bc7a43d67c`, 1 commit(s) in
range* — i.e. the culprit is `096da361dd93` ("fix(A): ParamCount carries a
type…").

## Why that commit cannot be the cause

- **It never moved the pin.** `lib-test` builds everything with `$(PXX_STABLE)`
  = `stable_linux_amd64/default/pinned`, last changed by `da44f561e` (v344).
  `096da361dd93` touches `compiler/parser.inc` and `compiler/ir_codegen386.inc`,
  which only affect a compiler built at HEAD — not this job.
- **Its Makefile lines went to a different target.** The 7 added lines land in
  `test-core` (the `test_paramcount_for_limit` steps, one of them an i386 cross
  build). They add no work to the `lib-test` recipe that timed out.

## And nothing in the job actually hangs

Measured each step around the cut point (the capture stops right after
`tk-nilpy: ok`, so the next recipe step is `lib_codecs`):

| step | result |
| --- | --- |
| `pinned test/lib_codecs.npy` build | ok, seconds |
| running it | `codecs ok`, exit 0 |
| `python3 test/lib_codecs.npy` (the CPython oracle beside it) | `codecs ok`, exit 0 |

So no step hangs. The job simply exceeds its total budget: `lib-test` is one
very large make target, and the run `wall` has been pinned at 1142–1145s at
EVERY sha since (`42e147157b60`, `7111221470d4`, `1a181203b094` — all RED, all
`new_red: 0`), which is the shape of a cap being hit rather than of a failure
being reproduced.

## The tool issue, which is the actual ticket

1. **A timeout is a duration signal, so bisecting it is not sound.** Whether the
   job crosses its budget depends on load, not only on the commit — this box also
   ran a dev session's compiles and `gate.sh quick` runs all day, and CLAUDE.md
   already records that concurrent work makes every compile 2-3x slower. Bisect
   converges on whichever commit straddled the threshold and reports it with the
   same confidence as a genuine first failure.
2. **The report does not distinguish them.** `(timeout)` appears as a small
   parenthetical next to `first failure:`; the STILL-RED list does not carry it
   at all. Suggestions, in the owner's hands: refuse to bisect a timeout-only
   job (or mark the result advisory), say `TIMED OUT after Ns` in the STILL-RED
   line, and record the job's measured duration next to its budget so slow-creep
   is visible before it becomes a red.
3. Worth checking separately whether `lib-test` should be SPLIT — one job whose
   sources are `crtl_exp2.c examples/tk/hello.npy +5` is broad enough that its
   name misdescribes what failed, which is the second half of why this reads as
   a C/math regression.

`test-nilpy#src:test/test_nilpy_pow_matches_cpython.npy` is the other STILL-RED
from the same run; its bisect range is 32 commits and it is NOT analysed here —
it may well be a real regression and deserves its own look.

## Gate

Track T's own: `tools/testmgr.py --tier full` green (T escapes the full-suite
hook with `PXX_TRACK=T`), plus whatever the owner adds for the report format.

## 2026-08-16 — FIXED (Track T). Confirmed the diagnosis first, then all three suggestions

### Confirmed, independently

Both facts in this ticket are true at once, which is the confusing part:
`lib-test` passes **167/167 standalone** against pin 344, and the full tier is
**still RED** on `lib-test#src:test/crtl_exp2.c (timeout)`. Not a contradiction
— the standalone run has the box mostly to itself; inside a 2500-job full tier
it does not.

The `wall` evidence holds and is the clincher: **1133.3 / 1141.9 / 1145.5 /
1143.8 / 1142.2 / 1141.2** across the last six full runs, at six different shas.
A failure that reproduces varies with the tree; a cap being hit does not.

### One correction to the ticket's reading of the ndjson

The row and the report do not *disagree* — the row is **silent**. `still_red`
was never written to `runs-<host>.ndjson` at all; only `new_red` and `fixed`
were. So a long-lived red, whose steady state is "no transitions", produced a
row saying `RED` and naming nothing. That is arguably worse than a
disagreement, because nothing looks wrong. Fixed below.

### What landed

1. **A timeout is no longer bisected.** `bisect_step` skips a regression whose
   recorded status is `timeout`, printing why. Bisect assumes the signal is a
   function of the tree; a timeout is a function of the tree AND the box, so the
   search converges on whichever commit straddled the budget that day.
   **Skipped rather than marked advisory** — an advisory range still gets read,
   and a wrong sha in a ticket costs more than an absent one. The job stays open
   in the ledger and still reports RED; it just stops manufacturing a culprit.
   Required carrying the failure kind onto the ledger entry (`status`), which it
   did not previously keep.

2. **The lists say so.** `TIMED OUT` now appears on the NEW-RED / STILL-RED
   line itself, not only in the `first failure:` parenthetical:

   ```
   - lib-test#src:test/crtl_exp2.c — test/crtl_exp2.c +5  **TIMED OUT**
   - test-nilpy#src:test/x.npy — test/x.npy
   ```

   Deliberately a separate `listed()` helper rather than folding it into
   `label()`: the first-failure line prints the status in its own parenthetical
   and would otherwise read `**TIMED OUT** (timeout)`.

3. **Slow-creep is visible before it is a red**, which is the part that actually
   prevents a recurrence. testmgr now annotates a job that PASSED while eating
   most of its budget, and states the budget when one does time out:

   ```
   PASS     some-job     unit   74.1s  ...  NEAR BUDGET (74s of 90s)
   TIMEOUT  injected-hang#00  unit  10.2s   budget was 10s
   ```

   A job at 80% of budget becomes a red on the next busy day, and that red then
   looks like a regression at whatever commit happened to be under test. Naming
   the headroom while it is still green is the only cheap moment to notice.

4. **`still_red` is written to the ndjson**, so the machine-readable archive can
   answer "what was red at this sha?" without replaying every row before it.

### Verified

- `--tier quick` GREEN, unchanged.
- `--tier quick --inject-hang`: `TIMEOUT injected-hang#00 unit 10.2s budget was 10s`.
- `write_report_md` on a synthetic two-job report: the timeout row carries
  `**TIMED OUT**`, the plain failure does not, and the marker appears exactly
  once (not duplicated onto the first-failure line).
- `bisect_step` on a synthetic timeout regression returns without doing work and
  prints its reason.

### NOT done, and left in the ticket

Suggestion 3 — **splitting `lib-test`** so one job's sources are not
`crtl_exp2.c examples/tk/hello.npy +5`. Agreed it is the second half of why this
reads as a C/math regression, but it is job-identity surgery: renumbering
`lib-test`'s 167 jobs migrates every key in tstate
([[bug-t-optdiff-positional-sharding-migrates-job-identity]]), so it wants doing
deliberately while the target is green, not folded into a report fix. Worth its
own ticket.

**These changes are in `tools/twatch.py` and do not take effect until the
daemon restarts** — twatch reads code once at process start; only `interval` /
`autoticket` / `no_bisect` reload live. The testmgr half is live immediately,
since twatch re-executes testmgr per cycle.

### Correction to the "NOT done" note above

That note said splitting `lib-test` "renumbers 167 jobs, migrating every key in
tstate". Overstated: `job_key` returns `sel` (`<target>#src:<first source>`),
not the positional name, so a split migrates only the jobs whose FIRST source
changes, and `gone_keys` closes those loudly as GONE rather than silently. Split
out with the corrected reasoning and a recorded baseline as
[[chore-t-split-lib-test-into-jobs-that-name-what-failed]].

### Resolved with one operational step outstanding

Resolving rather than leaving this in `backlog/`: the fix is landed and tested,
and a ticket whose fix has shipped but which still sits in the ready queue is
the shape that gets picked up twice.

The outstanding step is not ticket work: **the twatch half needs a daemon
restart** to take effect. The watcher clone has already pulled the code
(`6a276ff63`); the restart is gated on an idle window per the restart protocol —
no children and an attached HEAD, confirmed twice — because a SIGKILL mid-test
is what left the clone wedged on 2026-08-04. Until then twatch keeps bisecting
the timeout, so expect possibly one more innocent-commit range before it stops.
The testmgr half (NEAR BUDGET, the budget on a timeout) is live immediately,
since twatch re-executes testmgr every cycle.

## Log
- 2026-08-16 — resolved, commit 8e20d7372.

## 2026-08-16, later — a controlled measurement of the co-tenancy effect

The `wall` argument above rests on a series taken while the box was busy, which
invites the obvious objection: maybe the tier really is slow. Two runs later in
the day answer it, and they are a genuine control — **same tier, same box, same
day, one variable**:

| native tier run | box | wall |
| --- | --- | --- |
| sweep 1 | quiet | **403.1s** |
| sweep 2 | watcher running its own cycles alongside | **791.6s** |

Nearly 2x from co-tenancy alone. That puts the full tier's 1141-1145s series
comfortably inside what a busy box explains, with no slow tier required.

**Be precise about what this establishes, because it is not quite the ticket's
claim.** Both datapoints come from a box where one of the two parties measuring
was itself the contention. So what is established is that **co-tenancy dominates
this measurement** — a strong result, and enough to make bisecting a timeout
unsound, which is what the fix rests on. What is NOT established is the absence
of slow-creep underneath: a signal smaller than a 2x swing is invisible to
anything run today.

That residual is what the `NEAR BUDGET (Ns of Ns)` annotation added by this
ticket exists to catch, and it will answer the question the only way it can be
answered — by accumulating, on runs nobody is perturbing, rather than by another
argument about a wall number.
