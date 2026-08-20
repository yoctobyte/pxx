---
slug: bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic
track: T
type: bug
prio: 55
status: done
blocked-by: []
summary: "MEASURED 2026-08-19: option 2 (map exit 124) is unimplementable as written — zero of the ten sites propagate 124 to make, and the uforth corpus rows report a timeout as a false pxx-vs-CPython DIFF at recipe exit 0. Option 3 (record duration) was ALREADY DONE; the real gap is exp_dur missing from the report; the recipe markers are not T's lane. Original: ten `timeout N` calls are hardcoded INSIDE Makefile recipes, so they fire within make and surface to testmgr as an ordinary `fail`. Every piece of testmgr's contention machinery — PEER_TIME_FACTOR budget stretching, co-tenant retry, the `timeout` status itself — is structurally unable to see them. That is why six separately-fixed timeout tickets did not stop the class recurring: all six fixed testmgr's OWN timeouts, and the inner ones were never in scope."
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

## 2026-08-18, Track T — a TRAP for whoever fixes this: it will break my timeout guard

Not yet started; recording an interaction found while verifying the dispatch,
because a fix could plausibly ship a regression without noticing.

**Measured now**, from plexus' live ledger:

```
test-nilpy#src:examples/tk/callbacks.npy | status: fail    | range: 1 | bad: 5215148bb454
lib-test#src:test/crtl_exp2.c            | status: timeout | range: 16
```

`callbacks` is recorded **`fail`**, not `timeout` — which is this ticket's thesis
demonstrated live: the inner `timeout 120` (Makefile:363, introduced by
`5215148bb`, verified) killed the process, make returned nonzero, and testmgr saw
an ordinary failure.

### The trap

`bisect_step` refuses to bisect any regression whose status is `timeout`
([[bug-t-a-timeout-bisects-to-an-innocent-commit]]). The callbacks bisect ran,
converged to one commit, and was **correct** — it landed exactly on the commit
that introduced the expensive step.

It ran only because the inner timeout was invisible. **Fix this ticket, and that
same bisect gets refused** — a correct, useful result suppressed by a guard
written for a different shape.

### The distinction the guard is missing

Two timeout shapes, and only one is unbisectable:

| shape | example | is the bisect sound? |
| --- | --- | --- |
| the expensive step exists across the WHOLE range; the budget is straddled somewhere in the middle | `crtl_exp2` | **No** — the landing is wherever load tipped it, arbitrary |
| the range SPANS the commit where the job started doing the expensive thing | `callbacks` | **Yes** — the landing is exact |

So "a timeout is a duration signal, therefore not bisectable" — which is what I
wrote in `track-t.md` and encoded in the guard — is **too broad**. A
duration-driven failure does not by itself discredit a bisect; what discredits it
is the expensive step being present across the entire range.

Credit: the distinction is the coordinator's, from retracting its own prediction
that the callbacks bisect would name an innocent commit.

### What that implies for the fix

Whoever lands this should expect to touch `bisect_step` in the same change, or
the improvement will read as a regression the first time a legitimate
timeout-bisect is refused. A cheap discriminator, in the spirit of the existing
`pin_immune` check: **did the accused commit introduce or enlarge the job's
work?** If it added the recipe lines that run the thing, the landing is exact and
the bisect should stand. If every commit in the range already ran it, the
existing refusal is right.

Also worth noting the bisect result and this ticket's static reading (ten
hardcoded `timeout N` literals, Makefile:363 named as instance one) converge on
the same line by two independent routes — which is stronger evidence than either
alone, and is why "culprit" is the wrong word for `5215148bb`. That commit
introduced the first *execution* of tests that had only ever been parsed.
Running them was right; the fixed ceiling came with them.

---

## CORRECTION 2026-08-18 — the callbacks example is FALSIFIED. This ticket still stands.

Written by the coordinator, who filed this ticket overnight and put callbacks in its
supporting set. **That half was wrong and must be struck.** The thesis is not.

`regression-test-nilpy-callbacks` was resolved (`9f11b405d`) and the cause was **not a
timeout of any kind**. Measured:

| | |
| --- | --- |
| callbacks runtime under `xvfb-run` | **0.14s** |
| the ceiling it was said to be straddling | **120s** |
| slowest of 20 consecutive runs | 120ms |
| output vs `callbacks.expected` | **20/20 byte-identical** |

A ~1000x margin. No amount of tier contention closes that, and the 20/20 also closes the
*other* arm of the fork this ticket recorded ("timeout vs nondeterministic output").
Neither arm was the answer.

The real cause: `testmgr`'s `split_jobs` merges a producer with its consumer by
union-find over shared **literal** `/tmp` paths. The tk block RUNS three binaries but
COMPILES one, and reached the other two as `$(TESTTMP)/$$bin` — a shell variable — so no
shared token appeared, the jobs were never merged, and the callbacks job ran a binary
nothing had built in its scratch. The recorded log tail said so all along:

```
/usr/bin/xvfb-run: 200: /tmp/.../test_nilpy_tkinter26: not found
```

A missing binary. **A timeout kill is rc 124 and silent** — that is the discriminator,
and it was in the record the whole time. It read as timeout-shaped because everything
around it was.

### What to strike, and what survives

- **Strike** every use of `callbacks` as evidence — notably the "range SPANS the commit
  where the job started doing the expensive thing → landing is exact" row in the table
  above. That row's example is now known not to be a timeout at all.
- **Keep** the thesis and rest it on `crtl_exp2` (a genuinely recorded `timeout`, range
  16) plus the two unattributable pin-verify reds. A `timeout` inside a make recipe
  really is invisible to the contention machinery. That is real and separate.
- Note the ticket already observed that callbacks was recorded **`fail`**, not
  `timeout`, and treated that as a wrinkle in the thesis. **It was the tell.** Recorded
  because noticing a datum does not equal weighing it.

### The methodological failure worth keeping

Two independent routes — the bisect (`5215148bb`) and a static reading of the recipe
(`Makefile:363`) — converged on the same `timeout 120` line, and that agreement was read
as confirmation. It was not. `5215148bb` introduced the **first execution** of these
tests, and with that execution came BOTH a 120s ceiling AND a three-binary dependency
spelled through a shell variable. **Two candidate mechanisms entered in one commit**, so
no amount of agreement between methods that both land on the commit can separate them.

Convergence localises; only a measurement discriminates. The duration was never taken
until the ticket was actually worked — one `time` invocation would have killed the
timeout theory at the start.

This is the SECOND time in one day that a commit was read as the cause when it was the
**uncoverer** — see `5b43ad800`, where an iterative rewrite exposed a latent unassigned
`Result`. Both times the commit genuinely introduced the *conditions* under which an
older or adjacent defect became visible. Worth a standing habit: when a range is one
commit wide, ask what that commit made possible for the first time, not only what it
changed.

## Measurement 2026-08-19 (plexus-T): option 2's premise is false at every one of the ten sites

Fix option 2 above says "map `timeout`'s exit 124 to a distinguishable marker". Before
starting it I checked the cheapest possible version of that — **does the 124 already
reach us?** — because if make surfaced it, the whole fix would be a log-reading rule in
testmgr, needing no Makefile change and therefore no other lane.

In a scratch Makefile it does:

```
slow:
	timeout 1 sleep 5
→ make: *** [Makefile:2: slow] Error 124
```

distinct from `Error 1` (plain fail) and `Error 127` (missing binary). **That fact is
true and it is about the wrong subject.** It describes a recipe whose failing command IS
the `timeout`. Not one of this ticket's ten sites has that shape. Every one of them
swallows the 124 first, and they do it in four different ways. Measured, each as a
scratch recipe reproducing the real line's shape:

| site(s) | shape | what make reports | is the timeout recoverable? |
| --- | --- | --- | --- |
| 2408, 2541, 3538 | `test "$$(timeout N ...)" = "..."` | `Error 1` | **no** — command substitution discards the status; what fails is `test` |
| 402 (tk) | `timeout 120 ... \|\| { echo "... EXITED NONZERO under Xvfb"; exit 1; }` | `Error 1` | **no** — but the log line is distinctive, yet conflates a timeout with any nonzero exit |
| 8926 (lua cross) | `timeout 120 ...;` then `diff` | `Error 1` via `fail=1` | **no** — a truncated `got.txt` fails the diff; a timeout is indistinguishable from wrong output |
| 9321 (uforth smoke) | `...; rc=$$?;` then `echo "FAIL (exit $$rc)"` | `Error 1` | **YES** — the log literally contains `(exit 124)` |
| 9338/9339, 9357/9358 (uforth corpus) | backgrounded, `wait $$pp \|\| true`, then `diff` | **exit 0** | **no** — see below, and this one is worse than invisible |

So: **zero of ten propagate 124 to make; one of ten leaves a readable marker in the
log.** Option 2 cannot be implemented on testmgr's side alone. It needs an edit at each
recipe — which is `Makefile`, i.e. **not Track T's push lane** (T touches
`tools/testmgr.py` / `tools/twatch*` / `tools/fuzz.sh` / `tools/pasmith*` / `tstate/**`
and nothing else). See the lane split at the end.

### A third severity class this ticket did not have: a timeout wearing another lane's costume

The uforth corpus rows are not merely invisible. Measured with a scratch recipe of
exactly that shape (a producer truncated at 1s against a complete oracle):

```
	( timeout 1 sh -c 'echo a; sleep 5; echo b' ) > p.out 2>&1 & pp=$!; \
	( sh -c 'echo a; echo b' )                    > c.out 2>&1 & cp=$!; \
	wait $pp || true; wait $cp || true; \
	if diff -q p.out c.out >/dev/null 2>&1; then echo "  same"; else echo "  DIFF f"; ...

→   DIFF f
    @@ -1,2 +1 @@
      a
    -b
    (recipe exit status: 0)
```

`wait $$pp || true` discards the 124, the kill truncates `p.out` mid-stream, and the
truncation is then reported as **`DIFF <file>` — a pxx-versus-CPython divergence** and
counted into `bad`. The recipe exits 0, so testmgr does not even see a fail.

That is a strictly worse failure than the two the ticket already describes. It does not
lose a signal; it **manufactures a false one, in a lane that is not T's.** A NilPy
divergence report against the CPython oracle is exactly the kind of finding T files to
Track N, and whoever picks it up chases a frontend bug that is really a machine under
load. Note the symmetry with the 2026-08-18 CORRECTION above: that one struck a *false
timeout attribution*; this is the reverse, a real timeout disguised as a miscompile. The
class is the same — **a red whose stated subject is not its actual cause** — and both
directions are live in this one ticket.

### What this changes about the fix

- **Option 3 as written is ALREADY DONE — and the same premise check caught it, on the
  second try.** `testmgr.py:4266` has put `"dur"` (plus `"cpu"` and `"mem"`) in every
  report job dict all along. "At minimum, record the duration" needs no work.

  What is missing is the **baseline beside it**. testmgr learns an EWMA expected duration
  per job (`Job.exp_dur`, set at dispatch, `testmgr.py:2045`) and already uses it for a
  console note — `SLOW (expected 40.0s)` at `:4109`, `expected %.0fs` on a fail at
  `:4130`. Neither reaches the report. So the terminal in front of whoever launched the
  run can say "361s, expected 40s", and every downstream consumer — twatch, a cascade
  ticket, a human reading the JSON tomorrow — sees `"dur": 361.0` with nothing to compare
  it against, and cannot distinguish contention from normal without rebuilding the
  history testmgr already has.

  So the revised first fix is **one field: put `exp_dur` in the report job dict** (T,
  testmgr, self-contained, no Makefile). That is what makes the `wait || true` rows
  legible: a corpus job that normally takes 40s and took 361s reads as contention even
  though its own recipe insisted it exited 0. It still does not *distinguish* a timeout —
  it makes one visible to anyone reading the report, which is more than exists today.
  Note the published `tstate/*.json` is deliberately status-only, so this lands in the
  report, not there.
- **Option 2 splits by lane.** The marker has to be written where the `timeout` is:
  `test/`-suite recipes and the uforth corpus → the lane owning those tests, tk → B, lua
  cross → the target owner. T files these; T does not edit `Makefile`. The single
  exception is 9321, whose `(exit 124)` is already in the log and could be read by a
  testmgr rule today — but a rule that recognises exactly one of ten sites is worth less
  than the duration, and risks reading as coverage it does not have.
- **The `bisect_step` trap is unchanged and still gates option 2.** Nothing measured here
  touches it.
- **Recommended split before anyone starts:** keep this ticket for option 3 (T, testmgr,
  self-contained), and file the recipe markers as a separate ticket per owning lane with
  the table above as the work list. As written, this ticket cannot be completed by its
  own track, which is why it has sat at p55 without being taken.

### Method note

The premise check cost two scratch Makefiles and about a minute, and it inverted the
recommended fix order. Then it ran a second time, on my own replacement recommendation,
and caught that too: I wrote "option 3 rises to first" without checking whether option 3
was already implemented, and it was — one grep away, in the same file I had just been
reading. Twice in one sitting, the same shape: a fix proposed against a remembered model
of the code rather than the code. The failure it avoided is the one this repo keeps paying for:
`Error 124` was a true, verifiable, easily-measured fact that would have gone into this
ticket as justification for a fix that could not have worked on a single real site.
**Measure the subject, not a model of it** — a scratch reproduction is only evidence
about the real code when it reproduces the real code's *shape*, and here four distinct
shapes all needed reproducing separately.

## Landed 2026-08-19 (plexus-T): the baseline is in the report

The revised first fix from the section above, implemented. Track T's own tooling, so no
ticket claim was needed — but it is recorded here because it is this ticket's option 3,
and because what it does NOT do matters as much as what it does.

- **`report_job()` extracted** from the inline dict comprehension in `main()`. The report
  is the only part of a run that outlives the run, and until now its shape could not be
  exercised without a full tier. Pure extraction, no behaviour change.
- **`exp_dur` added** to every job entry: testmgr's learned EWMA, the number it has been
  printing to the console as `SLOW (expected 40.0s)` and throwing away. `None` when the
  job has no learned duration, never `0.0` — "we have never measured this job" and "we
  expect it to take no time" are opposite claims, and a consumer computing `dur/exp_dur`
  must be made to handle the first rather than silently divide.
- **`tools/report_exp_dur_devtest.py`** — 14 guards. Non-vacuity checked by deleting the
  field in a scratch copy: **10 of 14 go red, all by name.** The first version failed the
  neuter with a `KeyError` traceback instead of named FAILs, which reports where it broke
  but not what; reading the field through `.get()` fixed that. One check was dropped
  during the same pass for restating its predecessor — a guard that repeats the one above
  it inflates the count and covers nothing.
- **Incidental defect found by the guard, fixed:** `"dur"` was computed under
  `if j.t0 and j.t1`, but the unset sentinel is `None` (`Job.__init__`), so a timestamp of
  exactly `0.0` was reported as a zero-duration job. Unreachable today —
  `time.monotonic()` is uptime — which is exactly why it would have survived to bite
  whoever reused this on a clock that does start at zero. Now `is not None`.

### What this does and does not buy

It makes a Makefile-inner timeout **legible**, not **detectable**. A uforth corpus row
that normally takes 40s and took 361s now says so in the JSON, so a human or a triage
pass can see contention where the recipe insisted it exited 0. Nothing yet *acts* on the
ratio: `PEER_TIME_FACTOR` stretching, `_retriable_contention()` and the `timeout` status
are still structurally unable to reach inside a recipe, exactly as the top of this ticket
describes. That gap needs the recipe-side markers, which are `Makefile` edits and so not
Track T's push lane.

**This ticket stays open** for that half. What is left is the table in the measurement
section above, split per owning lane.

---

## CORRECTION 2026-08-20 (plexus-T) — the uforth row's "exit 0" is wrong. The severity claim is not.

The measurement table above reports, for the uforth corpus arms, *"what make reports:
**exit 0**"*, and the prose concludes *"the recipe exits 0, so testmgr does not even see
a fail."* **That is false about the real recipe.** `Makefile:9437` ends the target with:

```make
	if [ "$$bad" != "0" ]; then \
	  echo "test-uforth: FAIL — $$bad of $$((ok+bad)) corpora differ from CPython"; exit 1; \
	fi
```

A `DIFF` increments `bad`, and `bad != 0` exits 1. **testmgr does see a fail.**

The scratch reproduction that produced the `exit 0` reproduced the *comparison block* and
stopped there — it never included the trailing gate that reads `bad`. So the measurement
was true about the fragment it ran and false about the subject it was cited for.

Note what this is: the ticket's own method note, one paragraph below the table, says *"a
scratch reproduction is only evidence about the real code when it reproduces the real
code's shape, and here four distinct shapes all needed reproducing separately."* It was
right, and the count was five — the fifth shape was the whole-target gate that the
per-comparison shape sits inside. **The premise check that caught two errors did not run
on its own output.**

**What survives, unchanged and unweakened:** the uforth arms discard `timeout`'s 124 via
`wait $$pp || true`, the kill truncates `p.out` mid-stream, and the truncation is
reported as `DIFF <corpus>` — a pxx-versus-CPython divergence. That is still the worst of
the ten sites, still manufactures a false finding in another lane, and is now filed as
[[bug-n-a-uforth-corpus-timeout-is-reported-as-a-cpython-divergence]]. The correction is
to *how the false red arrives* (as a fail carrying a divergence, not as a silent pass),
not to *whether it arrives*.

## Landed 2026-08-20 (plexus-T): the duration is now ACTED ON, not just recorded

The 2026-08-19 entry made an inner timeout **legible** (`exp_dur` beside `dur` in the
report) and closed by saying it did not make one **detectable** — that the rest needed
recipe-side markers, i.e. `Makefile`, i.e. not this lane. That was one step too
pessimistic. There is a discriminator entirely inside `tools/testmgr.py`.

`Manager._retriable_contention()` already states the governing principle — *"a
kill/timeout while a co-tenant run was live is a statement about the BOX, not the
artifact"* — and is reachable from exactly two places: `rc < 0` with a signal **we**
sent or observed, and **our own** timeout. An inner `timeout` is neither. But the
baseline that landed yesterday supplies the missing third route:

- **`Manager._inner_timeout_shaped(job, now)`** — a FAILED job that has passed on this
  box before carries a learned EWMA. A failure that ran `INNER_TIMEOUT_RATIO` (3.0) times
  that long, above an `INNER_TIMEOUT_FLOOR` (20.0s), is **duration-shaped** rather than
  value-shaped. That is the fact the exit status was supposed to carry and does not.
- **The call site conjoins it with `_retriable_contention`**, deliberately, and that
  coupling is the whole safety argument. "Took 9x as long and failed" on an *idle* box is
  a plausible **performance regression**, and retrying it would mask the one finding a
  duration signal is genuinely good at surfacing. The peer gate is what makes the shape
  safe to act on; the shape alone is not.
- **Fails closed.** No learned duration — a job that has never passed here — means no
  discriminator and no retry.
- **It does not change the STATUS**, and that omission is load-bearing. Calling these
  `timeout` is the more honest word and is the wrong move: `bisect_step` refuses to
  bisect a timeout ([[bug-t-a-timeout-bisects-to-an-innocent-commit]]), so relabelling
  would silently suppress bisects that are sound today — the exact TRAP this ticket
  recorded on 2026-08-18. Retry the job; leave the verdict spelled as it was.

`tools/testmgr_inner_timeout_retry_devtest.py` — 17 guards, milliseconds, no tier.
Non-vacuity by four independent neuterings of production: dropping the floor reddens 1,
forcing the shape true reddens 2, setting the ratio to 1.0 reddens 2, and **removing the
contention gate from the call site reddens the guard written for exactly that** — the
last one matters most, because no runtime assertion inside the method can see its own
caller, so that guard reads the source. Smoked with a live `--tier quick` (16/16, and the
run happened to share the box with the watcher, so the co-tenancy path was exercised).

### What this covers, and the two sites it cannot

Covered: every site whose failure is a plain `Error 1` — the three `test "$$(timeout N
...)"` comparisons and the tk `|| { ...; exit 1; }` — **when a peer run was live**. Under
contention they now retry instead of going red, which is what the machinery was always
supposed to do for them.

Not covered, and not coverable from here: the two sites that report a **diff**.
`test-uforth`'s corpus arms and `test-lua-cross` both truncate a captured stream and then
compare it, so the red's stated subject is a NilPy divergence or a cross-backend
mismatch. A duration signal can say the box was busy. It cannot say *the comparison
should not have been made* — only the recipe saw the 124.

## Resolution 2026-08-20 — T's half is complete; the recipe half is filed per lane

Split as this ticket's own measurement section recommended.

- **Done here (T, `tools/testmgr.py`, self-contained):** option 3 plus the baseline
  (2026-08-19), and the duration discriminator with its contention gate (above).
- **Filed out, with the measured table as the work list:**
  - [[bug-n-a-uforth-corpus-timeout-is-reported-as-a-cpython-divergence]] (p55) — the
    three uforth ceilings, headlined by the false `DIFF`, plus `test-nilpy`'s three.
  - [[bug-a-a-lua-cross-timeout-is-reported-as-wrong-output-from-the-backend]] (p50) —
    `test-lua-cross`'s truncated-stream diff, plus `test-core:3553`.

Both carry the fix shape (capture the status, branch on 124 *before* comparing) and the
standing warning against raising the constants. Six of the ten sites are N's, two are
A's, and the remaining two are the tk and lua ones already counted in those.

The ticket closes because **it can now be finished by the lanes that own the files**,
which is the thing it could not claim before: as filed it required an edit T is not
permitted to make, which is why it sat at p55 unclaimed for a day with a complete
diagnosis attached.

## Log
- 2026-08-20 — resolved, commit 536fb13c5.
