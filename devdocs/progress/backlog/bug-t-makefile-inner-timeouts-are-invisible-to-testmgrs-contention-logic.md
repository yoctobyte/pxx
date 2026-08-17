---
slug: bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic
track: T
type: bug
prio: 55
status: backlog
blocked-by: []
summary: "Ten `timeout N` calls are hardcoded INSIDE Makefile recipes, so they fire within make and surface to testmgr as an ordinary `fail`. Every piece of testmgr's contention machinery — PEER_TIME_FACTOR budget stretching, co-tenant retry, the `timeout` status itself — is structurally unable to see them. That is why six separately-fixed timeout tickets did not stop the class recurring: all six fixed testmgr's OWN timeouts, and the inner ones were never in scope."
---

# Makefile-inner timeouts are invisible to testmgr's contention logic

## The finding

`tools/testmgr.py` has a careful, well-reasoned discipline for distinguishing "this
artifact is broken" from "this box was busy":

- `effective_timeout()` (`:1986`) multiplies a job's budget by `PEER_TIME_FACTOR`
  when a co-tenant run is live — *"stretch rather than retry where we can"*;
- `_retriable_contention()` (`:1992`) states the principle outright: **"A kill/timeout
  while a co-tenant run was live is a statement about the BOX, not the artifact"**;
- a timed-out job gets its own status (`job.status = "timeout"`, `:2125`), rendered
  distinctly (`:2440`) and reported with the budget it blew (`:3881`).

**None of it can reach a timeout written inside a make recipe.** There are **ten**:

    Makefile:363    timeout 120 xvfb-run -a $(TESTTMP)/$$bin     <- the tk GUI jobs
    Makefile:2191   timeout 20  ...float_repeat_typeerror26
    Makefile:2324   timeout 60  ...str_repeat26
    Makefile:3321   timeout 20  ...writeln_nonfinite26
    Makefile:8521   timeout 120 tools/run_target.sh (lua)
    Makefile:8916   timeout 60  uforth smoke
    Makefile:8933-4 timeout 180 uforth differential (pxx + CPython arms)
    Makefile:8952-3 timeout 900 uforth blocktest (both arms)

When one of these fires, `timeout` kills the inner process, the recipe line returns
nonzero, **make** exits nonzero, and testmgr observes... a job that failed. Not a
job that ran out of time. So:

- the budget is **rigid under contention** — testmgr stretches its own budgets on a
  loaded box while the recipe's ceiling stays at a constant written months ago;
- `_retriable_contention` never fires, because the status is `fail`, so the one rule
  that exists for exactly this situation is skipped;
- the report cannot say `TIMEOUT`, so a reader cannot tell a blown budget from a
  wrong value — and a bisect treats it with the confidence of a real first-failure.

## Why this matters more than one flaky job

**Six tickets in `done/` are this concept**, each fixed where it was found:

    bug-t-a-timeout-bisects-to-an-innocent-commit                 (p45)
    bug-t-qemu-conformance-false-timeout-under-load               (p55)
    regression-testmgr-conformance-shard-timeout-under-load       (p60)
    bug-testmgr-aarch64-conformance-shard3-timeout-flake          (p35)
    bug-t-csmith-harness-reports-slow-as-a-timeout                (p35)
    bug-t-three-network-tests-flake-and-cost-real-debugging-time  (p45)

Six mechanisms for one concept is past "smell" and past "design flaw"
(`devdocs/dev/root-cause-over-microfix.md`). And they did not stop it: the night of
2026-08-17 produced **four more timeout-shaped reds** on the watcher box —
`crtl_exp2` (recorded timeout), two unattributable pin-verify reds that reproduce as
pass, and `test-nilpy#src:examples/tk/callbacks.npy`, which passes at HEAD under the
job's exact recipe with byte-identical output while the accused sha differs from HEAD
by prose commits only.

The reason the six fixes did not generalise is now visible: **all six repaired
testmgr's own timeout handling.** The inner ones were never in scope, because from
testmgr's side they do not look like timeouts at all.

`Makefile:363` is the worst of them: a **GUI binary under a virtual X server**, the
most load-sensitive shape in the suite, on a **fixed 120s** ceiling, inside a
2700-job tier.

## What would fix it

Roughly in order of cost, for Track T to choose between:

1. **Let the recipes inherit a scaled budget.** Replace the literals with a variable
   (`$(TEST_TIMEOUT_GUI)`, etc.) that testmgr exports per job, already multiplied by
   the same contention factor `effective_timeout()` applies. The budget then stretches
   on a loaded box exactly as designed.
2. **Make the inner timeout self-identifying.** `timeout` exits **124**; a recipe that
   maps 124 to a distinguishable marker (a sentinel line, or a dedicated exit code the
   harness reads) lets testmgr set `status = "timeout"` and re-enter
   `_retriable_contention` — the retry rule then covers these jobs for free.
3. **At minimum, record the duration.** Even without either fix, a red carrying its
   wall time makes "blew the budget" separable from "wrong output" by inspection,
   which is the fact tonight's stub was missing.

(1) and (2) compose; (3) is the fallback that stops the reader from having to re-run
the job by hand to learn which kind of red it was.

## Notes

- Not every one of the ten is a live problem — the uforth arms at 180s/900s are
  deliberate and generous. The defect is **structural**, not per-constant: none of
  them can participate in the contention logic, so each is one busy evening away
  from a false RED, and the fix is at the mechanism rather than the numbers.
- **Do not "fix" this by raising the constants.** That trades a false RED for a
  slower suite and leaves the reader unable to tell the two kinds of red apart — the
  cost the six closed tickets kept paying.
- Filed by the coordinator during the overnight cycle, from the callbacks red
  (`regression-test-nilpy-callbacks`, backlog). **T owns the tool**; the compiler is
  not implicated here — this is testmgr/Makefile harness work in T's own lane.
- Related: `bug-t-pin-verify-records-positional-job-numbers-and-a-stale-version-label`
  is the same family one level out — a report that preserves the verdict and discards
  the discriminator. This ticket is the *duration* discriminator; that one is the
  *identity* discriminator.
