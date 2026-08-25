---
track: T
prio: 55
type: bug
blocked-by: []
summary: "SHAPE 2 SHIPPED AND DID NOTHING (see the 2026-08-19 correction: 9 saved, 0 carried, 100% loss — fixed under bug-t-a-saved-partial-is-evicted-by-the-next-run-of-different-work); this closes on carried_runs leaving zero, not on more code. Zero full-tier runs on HEAD in the 5h13m between 9bfb7fcfac03 (10:31:57Z) and ~15:45Z, while cross-target coverage read as fine because every native verdict was green. RE-MEASURED: the watcher is idle 54% of that window (~2.8h, 8x what a full tier needs) — breadth is not starved by pushes, it is queued behind pin verify, which needs a contiguous 21 minutes, gets idle slices with a median of 299s, and discards 100% on every abort. Breadth ran within minutes of pin verify finally retiring. Fix is resumability plus bounding consecutive idle, NOT reserving a slot."
---

# The push rate starves breadth coverage entirely

> **In one line: breadth was not starved by pushes — it was queued behind an
> unfinishable item.** `pin_verify_due` never goes false because branch 2 wants
> ~21 contiguous minutes, idle arrives in ~5-minute slices, and every abort
> discards 100%. Pin verify retiring and breadth starting within minutes, at an
> unchanged push rate, is what makes that a mechanism rather than a correlation.
> The title is the symptom and is kept for continuity; it names the wrong cause.


Measured 2026-08-19 by Track T (plexus-T), while answering two cross-sweep
requests that turned out to be unanswerable.

## The measurement

| | |
| --- | --- |
| last completed `full` tier | `9bfb7fcfac03`, **10:31:57Z** |
| testable pushes since | **76** |
| median interval between them | **1-4 minutes** |
| a native run | ~**246s** (~4 min) |
| a full run | ~**1250s** (~21 min) |
| `full` runs in that window | **0** |
| `native` runs in that window | **30** |
| `pin verify preempted by a push` | **33** |

**Pushes arrive faster than a fast verdict completes.** The watcher is therefore
never idle, and every phase that runs only when idle — the full-matrix backfill,
pin verification, fuzz — is starved. It is not aborting the full tier; it never
schedules it.

## Why this is a bug and not just a busy day

The dev-track protocol in `devdocs/dev/track-t.md` is *"confirm native yourself,
offload the matrix to T"*. Every lane's push discipline rests on the matrix
actually running later. Right now it does not, and **nothing says so**:

- `twatch --status` reports **UP**, correctly — it measures whether commits have
  been tested, and they have, at `native`.
- every native verdict is **GREEN**.
- so the fleet reads as fully covered while **cross-target coverage is zero** and
  has been for four hours.

That is a coverage claim whose boundary nobody is checking, which is the failure
`track-t.md` has a whole section about. Two live instances today: `a54259aab`
(the `stdarg.h` bodies moved from `static` to external — the open question is
whether i386/arm32/riscv32 resolve `__pxx_va_start_impl32` now) and `354f734c1`
(`PXXWriteFloatSci` across five backends). Both have native GREEN. **Neither has
been near a cross target**, and the requesting agent would reasonably have read
the greens as confirmation had it not been told otherwise.

Pin verification is the second casualty and arguably the worse one: 33
preemptions means `pinstatus` cannot name a freshly-verified pin, and the pin is
what every other track builds against.

## RE-MEASURED 2026-08-19 ~15:45Z — the headline held, the mechanism did not

Re-measured at current HEAD rather than quoted, because the numbers above are
five hours old. The window is the one that matters: from the last completed
`full` tier to the next one starting.

| | |
| --- | --- |
| last completed `full`-on-HEAD | `9bfb7fcfac03`, **10:31:57Z**, 1255.9s, GREEN |
| next `full`-on-HEAD start | ~**15:45Z** — **5h 13m later** |
| breadth starts in between | **0** |
| pin-verify starts in between | **16** |
| pin-verify *verdicts* in between | **1** (the last one, minutes ago) |
| native runs | 37, mean **236s**, total **2.4h** |
| aborted `full` runs | 13 — median **299s**, max **941s** |
| wall clock discarded by those aborts | **1.4h** |
| commits needing no gate (docs/tstate) | 18 |

**The headline claim holds: zero breadth runs in five hours.** The stated
mechanism above — *"the watcher is therefore never idle"* — is **wrong**, and
the correction changes which fix is right.

Native testing consumed 8740s of an 18900s window: the watcher was **idle 54%
of the time, about 2.8 hours of it.** Idle capacity exceeded what one full tier
needs (1256s) by roughly **8x**. Idle was never the scarce resource.

What is scarce is a *contiguous* window, and breadth never gets one because it
is not first in line for it:

1. `pin_mid` (branch 2) sits **above** idle-depth-on-HEAD (branch 3) in the
   ladder, deliberately — the pin is what B/C/D/E are building with right now.
2. Under the shipped default `mid_tier == tier`, that branch asks for a **full**
   tier on the pin: ~21 minutes.
3. Idle arrives in slices — the 13 aborted runs have a **median of 299s** and a
   max of 941s. A 21-minute job never fits, and every abort discards **100%** of
   the work.
4. So `pin_verify_due` never goes false, and **branch 3 is never reached.**
   Breadth is not starved by pushes directly; it is queued behind an item that
   cannot finish.

The confirmation is clean: pin verify finally retired (one 20.5-minute window,
`PIN v364 RED at full`) — and breadth started its first run in 5h13m **within
minutes of that**, with the push rate unchanged.

### What this does to the shapes below

- **Shape 1 (reserve breadth a slot) is now the wrong fix.** It spends
  fast-verdict latency to buy contiguity, when idle already supplies 8x the
  capacity needed. It treats a scheduling-order problem as a capacity problem.
- **Shape 2 (resumable) is the right one — and it must cover pin verify, not
  just breadth.** A perfectly resumable breadth would still never run, because
  branch 2 is ahead of it and unfinishable. Making *pin verify* resumable
  retires it, and unblocks breadth as a side effect.
- **New shape 4, cheaper than either: bound how much consecutive idle one
  unfinishable phase may hold.** Alternate, or cap it, so breadth gets turns.
  Costs fast-verdict latency exactly **nothing** — both phases are idle-only.
  Alone it does not finish a 21-minute job in 5-minute slices; with shape 2 it
  does.

Recommendation: **2 + 4**, neither of which touches the fast verdict. Shape 1
should be closed as measured-wrong rather than left open as an option.

### Self-inflicted instance, recorded because it generalises

`NOTEST_PREFIXES` is `("devdocs/", "docs/")`, so **`tools/**` is testable** —
correctly, since testmgr changes can change results. The consequence is that
**Track T's own tooling pushes preempt Track T's breadth run.** Pushing
`8ec77190c` cost the in-flight breadth run its first ~200 jobs. Until shape 2
lands, T tooling pushes should be batched, or held while a breadth run is in
flight.

## Shape (T's call, not yet decided)

Sketching rather than prescribing, because the trade is real — the fast verdict
is load-bearing and its latency IS the dev loop's latency:

1. ~~**Reserve breadth a slot.**~~ **CLOSED 2026-08-19 — measured wrong.** The
   proposal was to run the full tier after N fast verdicts and let pushes queue
   behind it, accepting fast-verdict latency as the price. The re-measurement
   above shows there is nothing to buy: the watcher was **idle 54% of the
   window, ~2.8 hours, about 8x the 1256s one full tier needs.** Capacity was
   never the constraint; contiguity was. This shape spends the one genuinely
   scarce resource (fast-verdict latency, which IS the dev loop's latency) to
   buy capacity already present eightfold.

   Left visible rather than de-ranked, because the next person to notice zero
   breadth will propose it again — it is the obvious fix, and it is wrong for a
   reason nobody can see without the idle number.
2. **Make the backfill resumable** rather than all-or-nothing, so a 21-minute
   run can complete across several idle slices instead of needing one contiguous
   window that never comes. More work; does not need to steal latency.
3. **Say so out loud.** Whatever else, `--status` and the tstate report should
   carry "no full-tier verdict for N hours" — the cheap half, and it converts a
   silent hole into a visible one. Worth doing even if 1 and 2 are declined.

(3) is separable and small; recommend it regardless.

## Note

Not caused by the two-phase design being wrong — the design says the fast verdict
wins and a backfill is discardable, which is right. What has changed is the
arrival rate crossing the point where "idle" stops occurring at all. A rate
threshold nobody set explicitly is worth naming before it is tuned.

## 2026-08-19 — shape 3 SHIPPED (the visibility half). 1 and 2 remain open.

The scheduling trade is untouched and still undecided; what is fixed is that the
hole is no longer silent.

**`--status` now prints a breadth line whenever a host has ever run a full
tier** — always, not only past the threshold, because the age IS the boundary of
the claim and a boundary nobody can see does not get checked:

```
tstate: host plexus  last 6fba42d69830 RED (native, ...); full through 9bfb7fcfac03 GREEN
tstate:   breadth — newest full tier is 4h old, 39 testable commit(s) behind
```

Past `BREADTH_STALE_SECS` (6h) it adds
`[STALE — no cross-target verdict on this tree; native GREEN does NOT cover
i386/arm32/riscv32/aarch64]`.

"Testable commits behind" counts what a gate OWES (`needs_test`), not raw
commits: on this repo the watcher's own publishes are most of the log, so a raw
count would read as alarming on a quiet day and bury the signal on a busy one.

**Published reports carry it too**, which is the half that matters days later —
a `native` report is what a reader reaches for, and GREEN on it says nothing
about the cross targets:

> **BREADTH IS 7h STALE.** The newest `full` tier on this host is 7h old, so no
> cross target has seen this tree. A `native` verdict covers x86-64 only — do
> not read it as matrix coverage.

A host that has **never** completed a full tier gets its own wording, because an
undefined age must not render as fine. A `full` report gets no banner — it *is*
the breadth run.

### The framing worth keeping, and why this was worth doing before the hard part

`--status` said UP and **was correct**: it measures whether commits were tested,
and they were. Every verdict said GREEN and each was true of the tier that
produced it. **The defect was never a wrong answer — it was a true answer to a
narrower question than the reader believes it is answering**, and this is that
shape at its most load-bearing, because CLAUDE.md tells every lane to run
`quick` + self-host and offload the matrix, and for four hours there was no
matrix.

The only thing standing between that and a wrong conclusion was one agent
warning another by hand. **A correctness property that depends on somebody
remembering is a habit, not a property**, and habits do not survive a context
clear.

**Gate:** `tools/twatch_breadth_visibility_devtest.py` (new, in
`make tools-devtest`) — the stale banner and its age, the never-ran wording, the
fresh case, the full-tier case, and that `secs_since` returns None rather than 0
on a malformed timestamp (0 would render "0h old" and mean the opposite).

**Still open:** shape 1 (reserve breadth a slot) and shape 2 (resumable
backfill). Both trade against fast-verdict latency, which is the dev loop's
latency, and neither should be decided from one busy afternoon.

## 2026-08-19 — shapes 4 and 2 SHIPPED. Every open shape is now closed or landed.

Approved by the coordinator on the reasoning rather than the authority
("neither shape touches fast-verdict latency"), which is the right test: step 1
of the ladder is the dev loop's latency and nothing here may spend it.

**Shape 4 — an unfinishable idle phase yields the slot instead of holding it**
(`546771cbe`). After `IDLE_YIELD_AFTER` (3) consecutive preemptions on one
target, a phase yields a single turn to the phase below it.

- *Three, not one.* Yielding every other turn would invert a priority that
  exists for a real reason — pin verify is the binary B/C/D/E are building with
  right now, while HEAD is a sha nobody has adopted yet.
- *Keyed on target as well as phase*, so a new pin starts with a full budget
  rather than inheriting the previous pin's exhaustion.
- *The yield is spent BEFORE the run it enables.* Clearing it afterwards would
  leave it standing through an abort — the likely outcome, since the same push
  rate is what earned it — and hand breadth the next slot too, turning a
  one-turn loan into the inversion this is careful to avoid.

**Shape 2 — an aborted run costs the work it had LEFT, not the work it had
done.** The expensive half turned out to be already built: testmgr handles
SIGINT, tears its jobs down, and **still writes its report**, verdict
`INTERRUPTED`, listing every job it had finished. `run_gate` returned before
reading it. So the fix is a carry-over, not a checkpointing engine:

- twatch saves that report as a partial keyed on `(sha, tier)`
  (`.testmgr/resume.json`, untracked);
- the next slice of the same work passes it to testmgr as `--resume`;
- testmgr skips the jobs it already decided and merges their verdicts into the
  report it finally publishes.

Three ways that could be wrong, each pinned by a check:

1. **Results not attributable to this binary.** A partial is only valid against
   a byte-identical compiler, so the partial carries the compiler's `sha256` and
   testmgr — the only thing that knows the bytes *before* any job runs —
   discards on mismatch. The invariant is real (the compiler is built through
   the self-host fixedpoint at the tested sha) but holds **at the default `-O`
   level**, which is the only level anything compiles `compiler.pas` at today; a
   tier that ever built it at another level would break it quietly, and
   comparing bytes is what turns that into a discarded partial instead of a
   wrong verdict. That assumption is stated at the check site, not just here.
2. **Carrying a job whose artifacts are gone.** The aborted slice ran in its own
   `RUN_TMP` and dropped it at exit, so anything a still-to-run job depends on
   must be re-run — transitively. This would not have failed loudly: it would
   have run a dependent against a missing artifact and reported an ordinary red.
3. **Laundering a carried RED into a GREEN.** The failure was decided in an
   earlier process, so this run's `rc` knows nothing about it. `carried_red()`
   is what stops the report carrying a red job while announcing green.

**The verdict is never partial.** An aborted run still publishes nothing at all
— `run_gate` still returns `(None, "aborted")` and the caller still records no
verdict. A partial is an input to the next run, not an output to the fleet.

### Counted, because the failure mode here is silence

A resume that always discards is **indistinguishable from one that works**: both
eventually produce full coverage, and the broken one merely costs what today
already costs. So `.testmgr/resume-stats.json` counts partials saved, runs
carried, testmgr-side discards, aborts that left no report (SIGKILL after the
30s grace), and supersedes; `resume_health()` prints the rates, not the events.
Same fix as the breadth banner, applied to its own machinery — *a property that
holds only because somebody remembered is a habit, not a property.*

### What shape 4 must not be credited with

It makes the lower branches **reachable, not fast**. It does not finish a
21-minute job in 5-minute slices; shape 2 is what makes the turns add up.
A metric will move when the daemon restarts and it will be tempting to read that
as the fix landing. **If breadth's first post-restart run is still an abort,
that is expected, not a regression** — the push rate has not changed.

**Gate:** `tools/twatch_idle_yield_devtest.py` (shape 4; pins both opposite
failure directions — yielding too eagerly and yielding permanently) and
`tools/twatch_resume_devtest.py` (shape 2; the three wrong-carry modes above
plus the counting), both in `make tools-devtest`.

**Status: shapes 1/3/4 done; shape 2 shipped, then measurably did nothing.**
1 closed as measured-wrong, 3 shipped (visibility), 4 shipped and working
(`idle_yield` counts on the live tstate). Shape 2 shipped as `e2449adc5` and
**delivered nothing at all** — see the correction below.

## Correction, 2026-08-19: shape 2 had a 100% loss rate

The line above once read "all four shapes resolved". That was written from the
code landing, not from the numbers, and the numbers say otherwise. From the
watcher clone at 20:23:12Z, over the feature's entire life:

    saved_partials 9 · saved_jobs 1420 · carried_runs 0 · superseded 9

Nine saves, nine supersedes, **zero carries.** Root cause: `.testmgr/resume.json`
was a single slot every gate run claimed, and `resume_arg()` deleted a partial
belonging to other work rather than declining it — so the push-driven native
verdict that *ends* an idle slice destroyed the pin-verify partial saved when
that slice was preempted. Filed and fixed as
`bug-t-a-saved-partial-is-evicted-by-the-next-run-of-different-work` (keyed
partial store, `PARTIAL_CAP`, read-only `resume_arg`).

So this ticket's own conclusion — "shape 2 is what makes the turns add up" — was
never in force. A 21-minute pin verify still could not complete in 5-minute
slices, for the whole period the fix was believed to be deployed.

**This ticket stays open on a NUMBER, not on code.** It closes when
`carried_runs` on the live clone leaves zero and a full tier lands off resumed
slices. Watching the stats file is the remaining work — which is what the stats
file was built for, and this correction is the first time it earned its keep.

## Measurement, 2026-08-20: the first half is met; the second half cannot be, for breadth

`carried_runs` has left zero. From the live clone at 04:24Z:

    saved_partials 16 · saved_jobs 3282 · carried_runs 1 · carried_jobs 15
    last_note: "resume: partial accepted — 15 job(s) already decided against
                this exact binary (1479b663dd15)"

So the keyed store works and the eviction bug is genuinely fixed. But **the one
carry was a pin verify**, and that is not luck. Breadth cannot carry, and the
proof is short enough to state in full:

1. Breadth targets `tested = st["last"].sha` — the newest sha the fast tier has
   verdicted (`twatch.py:5047`, used at `:5134`).
2. Breadth aborts through `make_preempted(clone, tested)` (`:3899`), which
   returns True only when a commit between `tested` and head passes
   `needs_test()` — i.e. touches anything outside `devdocs/` / `docs/`
   (`:3892`, `NOTEST_PREFIXES` at `:3602`).
3. That is the *same predicate* that makes `do_test` fire on the next cycle
   (`:5051`), which runs the fast tier at head and moves `tested` to it.
4. The partial is keyed `(sha, tier)` (`:1887`) and `resume_arg()` opens only
   that one file (`:755`, `:666`).

**⇒ the abort that creates a breadth partial is caused by the very sha move that
makes its key unmatchable.** Not a race, not a tuning problem: a breadth partial
is dead at the instant it is written. The only breadth path that can carry is
`STOP` — a daemon restart, where `tested` does not move. Pin verify carries
because it targets a *frozen* pin sha across slices.

Live, from the log, in one 40-minute window:

```
testing e0f9cb893fea (full)  -> aborted ->  64 jobs kept  -> key dead
testing 011e3904e52e (full)  -> aborted -> 537 jobs kept  -> key dead
testing ef3ea948003d (full)  -> aborted ->  15 jobs kept  -> key dead
```

616 jobs saved, 0 carried, and the newest full tier is `49a511e43271` at
2026-08-19T23:23:18Z — **5h12m stale** at the time of measurement, with five
pushes in the interval. The starvation this ticket names is live right now.

### The key is NOT too strict — do not "fix" it by keying on the binary

The obvious next move is to drop the sha from the key, since testmgr already
validates the partial against the compiler's **sha256** (`testmgr.py:1474`) and
that is the invariant that actually matters. **That would be unsound.** The
compiler sha256 answers "same binary"; it says nothing about the *corpus* or the
*harness*. `tested` only ever moves when a commit touches something outside
`devdocs/`/`docs/` — which means `compiler/`, `test/`, `tools/`, or `lib/`. The
sha256 covers the first. The git sha is what covers the other three, and a
carried verdict for `test_foo` measured against an old expected-output file is
exactly the wrong-answer-with-confidence this repo keeps paying for.

So the two-part key is correct as designed, and shape 2's near-zero carry rate
for breadth is the mechanism **refusing** to carry work it cannot attribute —
not a defect in it.

### What that means for this ticket

The close condition as written — "a full tier lands off resumed slices" — is
**unachievable for breadth by construction**, so it cannot be the bar. Shape 2
is doing its job on the path where carrying is sound (pin verify); breadth's
remaining lever is the one shape 1 already identified and this measurement
re-confirms: **contiguity, not capacity.** Idle time is abundant; a contiguous
21-minute window is not, because a push arrives every ~8 minutes and every push
restarts the ladder from zero.

Revised close condition: **a full tier lands within a working day of the sha it
tests, sustained over a week.** That is the outcome the ticket actually wants,
and unlike the old one it is reachable by more than one mechanism.

### Found on the way: a killed job was being published as a failed one

Reading the partials to write the above turned up
`ef3ea948003d-full.json` holding `selfhost-fixedpoint#00` as a 26.7s `"fail"`
after an eight-second run — an artifact of `teardown()`, not a verdict. Filed
and fixed separately as [[bug-t-a-killed-job-is-published-as-a-failed-job]],
because it is a phantom red on the **published** path too, not only on this
ticket's resume path.
