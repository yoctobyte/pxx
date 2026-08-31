---
track: T
prio: 45
type: chore
blocked-by: []
summary: "One lib-test job bundles several sources, so its tstate key names only the FIRST of them: `lib-test#src:test/crtl_exp2.c` is really `crtl_exp2.c examples/tk/hello.npy +5`, and a timeout in the tk step reads as a C-math regression. Split it so a job names what failed. Do it while lib-test is green — the baseline is recorded here."
---

# Split `lib-test` so a job's key names what actually failed

- **Type:** chore (job composition) — **Track T**
- **Opened:** 2026-08-16
- **Split out of** [[bug-t-a-timeout-bisects-to-an-innocent-commit]], whose
  suggestion 3 this is. That ticket fixed the timeout half; this is the
  "the name misdescribes what failed" half, deliberately not folded in.

## The problem

`lib-test#src:test/crtl_exp2.c` sounds like a C math test. Its actual sources
are:

```
test/crtl_exp2.c examples/tk/hello.npy +5
```

Seven sources in one job. `job_key` names a job by `sel`, which testmgr builds
from its **first** source — so a failure anywhere in those seven reads as
`crtl_exp2.c`. The timeout that prompted the parent ticket was measured to cut
right after `tk-nilpy: ok`, i.e. in a *different* source from the one the key
names, and it duly read to two separate readers as a C/math regression.

That is a real cost per incident: a triager starts in the wrong file, and the
auto-filed stub carries the wrong name into a ticket title.

## Correcting the parent ticket's stated reason for deferring

The deferral there said splitting "renumbers `lib-test`'s 167 jobs, migrating
every key in tstate". **That is overstated, and the correction matters because
it makes this job smaller than it was made to sound.**

Identity is NOT positional. `job_key` returns `j["sel"]` — `<target>#src:<first
source>` — precisely so that inserting a step does not renumber everything
([[bug-t-optdiff-positional-sharding-migrates-job-identity]] is about the
positional case, and `sel` is the fix for it). So:

- a job whose first source is unchanged keeps its key across a split;
- a job whose first source changes gets a **new** key, and the old one is closed
  by `gone_keys` as **GONE** — which twatch prints loudly and does not confuse
  with FIXED.

So the migration is bounded, visible, and already modelled. It is still worth
doing while green, but for the ordinary reason (no red should migrate, and no
phantom NEW-RED/FIXED pair should be manufactured), not because the whole
keyspace churns.

Evidence that the composition drifts on its own anyway: `lib-test` yielded
**166** jobs on 2026-08-14 and **169** today, without anybody splitting
anything. The keyspace is not static and treating it as precious is what has
deferred this twice.

## The baseline, recorded while it is fresh

This is the perishable part, and the reason the ticket exists now rather than
later:

| | |
| --- | --- |
| `lib-test` standalone | **167/167 pass**, 2 corpus skips, 1 flaky-on-retry |
| pin | **v344**, sha256 `47836e63248f1404` |
| recorded at | `be8844b95` |

**That green is the standalone kind.** The full tier is still RED on this same
job with a `(timeout)`, which is the parent ticket. So the precondition here is
"every lib-test job passes when given the box", which is what a renumbering
needs — not "the tier is green".

It is also not durable: the next change under `lib/**` can take it away, and the
job count has already moved three times this week. Renumber against this
baseline, or re-establish one first.

## Shape

Cut `lib-test` on the same boundary the other targets use — `COMPILE_RE`, which
already knows both `./compiler/pascal26` and the pinned spellings. The seven-source
jobs exist because several steps run between two compiler invocations, so the
question is whether those steps deserve their own boundary (a shell step that
runs a built binary, a python oracle beside it) or whether the recipe should
emit a compile per assertion. Prefer the former: it is a testmgr change and
stays in T's lane, where the latter is a Makefile change and is not.

## Done when

A `lib-test` failure's tstate key names the source that failed. Concretely: the
job that timed out after `tk-nilpy: ok` should be keyed on the tk step, not on
`crtl_exp2.c`.

## Gate

`tools/testmgr.py --tier full --job 'lib-test#*'` green before AND after, with
the job list diffed by key so every changed key is accounted for as an
intentional rename rather than discovered in tstate afterwards — the same
before/after comparison the enrolment used
([[task-t-enroll-libtest-demos-watcher]]: 5528 -> 5700, 0 reclassified).

## Recurrence 2 — 2026-08-18 (coordinator rerank 35 → 55)

The same false red is open again: `lib-test#src:test/crtl_exp2.c`,
`bad=eda43dea7629`, 16 in range. Proven innocent by the same arithmetic as the
parent ticket, and re-proven rather than recalled because **the pin moved twice
today** (v351 `a6d6dfb84`, v352 `b14da0847`), which is exactly the confound that
would make "it's just the timeout again" a wrong dismissal:

- `eda43dea7629` touches `Makefile`, `compiler/parser.inc`, one ticket, one test.
  It does **not** touch `stable_linux_amd64/**` or `lib/**`.
- Its Makefile hunk adds a **test-core** step (`./$(COMPILER) …`), not a lib-test one.
- `lib-test` builds with the **pinned** compiler, and at `eda43dea7629`'s own sha
  the pin was still pre-v351 — both pin commits are dated the following day.

So a Track P parser fix cannot reach this job, and the bisect landed on it for the
same reason as last time: **a timeout is a duration signal, so bisecting it
converges on whichever commit straddled the budget.**

**Why the rerank.** The parent ticket fixed the timeout half and this one was
deliberately left as the naming half at low priority. Two recurrences later, the
cost is not cosmetic: each one spends a coordinator's attention proving a green
job innocent, and the *next* one is the real hazard — a genuine C-math regression
under this key is now pre-discredited, because the standing prior is "that key
lies". A misleading name that has cried wolf twice is a correctness problem for
the reporting channel, not a tidiness chore. Still Track T, still "do it while
lib-test is green", baseline unchanged.

### Track T confirms the rerank — and checked the one thing that could have overturned it

Accepted, no push-back. The reporting-channel argument is the right one: a key
that has cried wolf twice makes the *next* red under it pre-discredited, and
that is a correctness problem rather than tidiness.

One check was needed first, because the "timeout is a duration signal" reasoning
above rests on a rule **narrowed hours earlier**. `track-t.md` now says refusing
a timeout-bisect is right only when the expensive step exists across the WHOLE
range; when the range *spans* the commit that introduced it, the landing is
exact (see `callbacks.npy` /
[[bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic]]).

That mattered here because this job's seven sources include
`examples/tk/hello.npy`, and `5215148bb` is what first made the tk tests
*execute* under `timeout 120 xvfb-run`. Had that commit fallen inside the range,
this bisect would have been the exact shape and the false-red conclusion wrong.

Checked against the live ledger:

```
range: f6fe47576842 … eda43dea7629  (16)
5215148bb in range: False
```

Outside it. So the tk step was already running throughout, the landing is
arbitrary, and the conclusion stands under the narrowed rule as well as the
old one.

Also worth recording for whoever splits this: **`pin_immune()` does not
exonerate `eda43dea7629`**, because it touches `Makefile` and `test/**`, which a
pin-built job does read. The proof above goes further — that the Makefile hunk
lands in `test-core` rather than `lib-test` — which is per-target hunk analysis,
deliberately NOT automated (`fix(T): refuse a bisect the pin proves cannot be
causal` records why: Make targets share variables and dependency edges, so
textual proximity is not causal isolation). A human-equivalent reading may do
what an unattended rule should not; the guard staying conservative is correct.

## Correction 2026-08-19 — the red under this key was never false

Track T (plexus-T), from measuring the job instead of its steps.

This ticket, and the parent, treat the standing red as a **false** one: a
duration signal, an arbitrary landing, a naming defect worth fixing for the
reporting channel. The first two are right. **"False" is wrong**, and the
distinction changes what this ticket is for.

`lib-test#src:test/crtl_exp2.c` has a learned EWMA of **107.5s** on `plexus`
against the **90s** `unit` class budget, and `Manager.__init__` kept the class
figure as a ceiling over a measured job — so the budget could not rise to fit and
the job was killed at 90s on every full tier. Not a flap, not load-dependent in
the way it looked: **permanent**, from whenever it crossed 90s.
[[bug-t-a-job-that-outgrows-its-class-can-never-pass-again]] has the mechanism
and the fix.

The inversion that hid it: the job takes **73.5s standalone** and ~107s among 24
jobs on 12 cores, while only a PEER CLONE's run stretches the budget
(`PEER_TIME_FACTOR`). Intra-run parallelism — the thing actually slowing it —
stretches nothing. So the job passed when the box was SHARED and failed when it
had the box to itself, and "green standalone, red in the tier" read as
contention when it was the permanent state.

**What this means for this ticket:**

- The "do it while `lib-test` is green" precondition is **satisfied and was all
  along** — the standalone 167/167 baseline recorded above is real, and the tier
  red never contradicted it. Nothing here is blocked on waiting for green.
- The two tickets were never independent. **Splitting would have fixed the red
  as a side effect**, by cutting the composite into pieces that each fit inside
  90s. The timeout fix removes the red now; the split is what stops the job from
  being a 23-line composite whose budget is a property nobody can reason about.
- The crying-wolf argument for the rerank **gets stronger, not weaker**. The key
  did not merely misname a transient failure — it misnamed a permanent
  misconfiguration as a C-math regression for three days, across two triages.

One correction to the baseline table while it is being relied on: the job's
first source is unchanged by a split of the tk steps only if the crtl_exp2
compile stays the head of its chunk. If the split puts the tk block in its own
job, `lib-test#src:test/crtl_exp2.c` **keeps** its key (and its metrics history,
which is keyed on `sel`) and a NEW key appears for the tk chunk with no history —
so the new job runs on its class default for its first two runs. Worth expecting
rather than discovering in tstate.
