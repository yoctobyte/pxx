---
track: T
prio: 60
type: bug
blocked-by: []
summary: "PASSLIKE = (pass, skip), so a job that SKIPped because its corpus was absent counts as the last GOOD sha. When the corpus later appears and the job runs for the first time, the range is computed from a sha where it never executed — manufacturing a regression window full of innocent commits. Cost a real hypothesis and four wrongly-implicated commits on 2026-08-27."
status: done
owner: pxx-a5
---

# A skipped job is PASSLIKE, so it becomes a false "last good"

Filed 2026-08-28 by frankB (Track B) out of the triage of
`regression-lib-test-lib-synapse`. **Track T owns the tool; I am filing, not
fixing.**

## What the range said, and what is actually true

`regression-lib-test-lib-synapse` reported bad `c52fc389fd97`, last good
`aca7f699288e`, **9 observable commits**, of which 5 touched `lib/` or the pin.
Every one of them is innocent:

- v388 (`e8b72f8afeb6`) and v389 (`325b4479070a`) fail **identically** on the
  job, so the pin move in the range did not carry it in.
- Rebuilding the *true* last-good state — `aca7f699288e`'s own `lib/` and
  `test/`, compiled with **v388**, the pin actually in force at that sha —
  **also fails**.

The defect is real (`bug-a-a-deep-unit-dependency-parses-with-a-spliced-token-stream`)
and it **predates the whole range**.

## Why the range was wrong

`tools/twatch.py:1514`:

```python
PASSLIKE = ("pass", "skip")
```

and the red predicate throughout (`:1729`, `:5028`, `:5206`, `:5496`) is
`status not in ("pass", "skip")`. So **a SKIP is indistinguishable from a PASS
when the last-good sha is chosen.**

`external/synapse` is in `CORPUS_ROOTS` (`tools/testmgr.py:1206ff`), so when that
tree is absent the three synapse jobs SKIP rather than fail — correct on its own
terms, and deliberate. But the two facts compose badly:

1. At `aca7f69` the full tier **did** run (`runs-plexus.ndjson`: `aca7f69 full
   RED`), and `lib-test#src:test/lib_synapse.pas` is **not** in that report's
   STILL-RED list.
2. That same tree, built with that same pin, **fails** when `external/synapse`
   is present — measured above.

Both can only hold if the job SKIPped at `aca7f69` for want of the corpus. It
was then treated as good, and when the tree appeared on plexus before
`c52fc38` the job ran **for the first time** and reported as a regression. It is
`plexus.json` that shows the corpus is present now: `lib_synapse_ssl` and
`lib_synapse_transitive_unit` both `pass`, so only the one `uses` shape fails.

**A first-ever run is not a regression, and the sha where a job did not execute
is not a last-good.**

## The shape of the rule, because this is not synapse-specific

Any corpus-gated job carries this: `library_candidates/**` and `external/**`
alike. The moment a corpus lands on a watcher box, every job it gates can file a
regression whose range is "everything since the corpus was missing" — bounded
only by how long the tree was absent. The code already knows the hazard in prose
(`twatch.py:1199`: *"a skipped job is invisible in a GREEN verdict"*;
`testmgr.py:124` records a job that printed `SKIP (no fpcsrc)` and *"PASSED for
its entire life without running once"*). What is missing is that the insight
does not reach the **last-good** computation.

Same failure mode as the one I hit earlier this session and wrote up as the
sentinel rule: **green that means "did not fail" is not the same as green that
means "ran and passed", and only the second can anchor a bisect.**

## Suggested direction (T's call, not mine)

Track last-good per job on **`pass` only**, keeping `skip` PASSLIKE for the
run-level verdict where it belongs. Then a first real execution after a corpus
lands has no prior good sha and files as **NEW / untested-before**, not as a
regression with a fabricated window. If a range cannot be anchored, saying so is
strictly better than naming nine commits that cannot have caused it — the
watcher already does exactly this for the "nothing testable changed" case
(`twatch.py:3173`).

## Gate

Track T's own tooling gate (its full tier green), exercised with quick tiers and
a scratch bare repo per the track's own rule — not run from a dev lane.

---

## Track T triage, 2026-08-28 — confirmed, and it is a FIFTH face of a closed ticket

Verified from the ledger rather than reasoned about. The open regression reads:

    job        lib-test#src:test/lib_synapse.pas
    first_seen false
    good       aca7f699288e        bad  c52fc389fd97
    pin_axis   2                   pin_built true
    range      9 commits

**`first_seen: false` confirms the diagnosis and rules out the neighbouring
one.** The job WAS present in the previous per-job map, so it did not arrive as
a never-seen job; it was present carrying `skip`. That distinction matters
because `diff_jobs` has a *second*, independent route to the same false
regression — `prev_jobs.get(n, "pass")` defaults an unseen job to *pass* — and
that route is already guarded. This red did not take it. The `skip` route is
the live one, exactly as filed.

### The part worth knowing before anyone starts on it

This is the **fifth** face of
`bug-t-a-blame-range-is-computed-from-what-changed-not-from-what-the-job-can-see`,
which is in **`done/`**, closed 2026-08-26 (`4672796d0`) with a table headed
*"All four faces, closed"*:

| face | fix |
| --- | --- |
| wrong anchor | `c68e6492e` |
| untestable commits in range | `cf7d805d4` |
| wrong axis (pin-built) | `4672796d0` |
| first-ever run inherits a range | `663214041` |

A fifth existed the whole time. That is not a criticism of the closure — four
faces were found, four were fixed, and the ticket says so honestly. It is a
warning about the shape: **this defect presents one face at a time, and each
looks like the last one.** The closing table's confidence is the thing to
discount, not its content.

The family question is one sentence, and it is already written in `diff_jobs`:
*the range is computed from what CHANGED without asking whether the job could
SEE it.* Face five is that a job which did not RUN also could not see it, and
`skip` is how "did not run" is spelled.

### Which makes the fix cheaper than it looks

The machinery this needs already exists and was built by the four previous
faces. The ledger entry above is carrying `first_seen`, `pin_axis`,
`pin_built`, `bad_untestable` and `no_testable_change` — five fields whose
entire job is to say "this range cannot mean what it appears to mean". Face
five is very likely a sixth field of the same kind plus a last-good selector
that requires `pass`, not a new mechanism. `tools/twatch_first_seen_devtest.py`
(9 cases) is the pattern for the guard, and the new one belongs beside it.

**The load-bearing constraint, and I would put it above the fix in priority:**
`skip` is correct as a run verdict and catastrophic as a last-good anchor. The
fix must separate those two readings rather than reclassify `skip` — moving it
out of `PASSLIKE` would fix the anchor by breaking the verdict, since a run
whose corpus is absent must still be able to come back GREEN. `diff_jobs`
already keeps the literal status in `now` for exactly this reason ("tstate
publishes `skip` as itself"), so the information needed to split the two
readings is already published; nothing has to be re-derived.

### Not reprioritised

Left at **prio 60** as filed. It manufactured a false signal rather than hiding
a true one, which is the worse failure mode — but it cost a triage, not a
week, and the four-line repro in the sibling Track A ticket is what the lanes
actually need next.

---

## Resolution — 2026-08-28, Track T (pxx-a5)

**Credit: filed by frankB (Track B)**, out of the `regression-lib-test-lib-synapse`
triage, correctly filing rather than fixing. The diagnosis in the sections above
was right in every particular and the fix follows it; the one place this went
further than the suggested direction is noted below.

### What changed

**`job_anchor(st, name)`** (new, beside `last_covering_sha`, which it supersedes
for this one use). It answers *"where did this job last RUN AND PASS?"* —
whereas `last_covering_sha` answers *"which earlier run's tier CONTAINED this
job?"*. Tier coverage is not execution, and the coverage answer is confidently
wrong exactly when the job never ran.

It returns three distinguishable states, and the third is the migration:

| return | meaning | caller does |
| --- | --- | --- |
| `(sha, "")` | it passed there | anchor the range at `sha` |
| `(None, reason)` | KNOWN never to have passed | open **no range** |
| `(None, "")` | no opinion — state predates the map | keep the old fallback |

Collapsing the last two would have blanked every range on the box for a cycle
on upgrade. They are separate, and a devtest asserts they stay separate.

**`st["job_last_pass"]`** — per-job sha of the last **literal** `pass`,
maintained beside `job_tier` and pruned with it. `skip` deliberately does not
advance it; a devtest asserts the predicate is `v == "pass"` and specifically
that it is *not* `v in PASSLIKE`, which would re-admit the bug one indirection
deeper.

**`range_for()`** consults the execution answer **before** any coverage
reasoning, and honours a refusal with an empty range. **`never_passed`** is
published on the ledger entry beside `first_seen`, so readers can see that a
range was withheld rather than merely absent.

### One place this goes past the ticket's suggested direction

The ticket proposed anchoring on `pass` only, which for the synapse case gives
an empty range. But consider **pass at A, skip at B, fail at C**: "previous
status was not a pass" yields *no* range, when the true answer is the **wider**
range `A..C`. Anchoring on the last *pass* rather than on the last *status*
gets that right, and errs toward the wide side — `last_covering_sha`'s own
docstring already states why that is the safe direction: *"a too-wide range
costs bisect steps; a too-narrow one can exclude the culprit, which is the
failure that matters."*

### `skip` was NOT reclassified, and that is the load-bearing part

`PASSLIKE` is untouched. `skip` remains pass-like for the run verdict and for
`reg_open`, because a run whose corpus is absent must still be able to come
back GREEN, and a box that legitimately cannot run a job must not hold a
regression open forever. **`skip` is correct as a verdict and catastrophic as
an anchor**, so the fix splits the two readings rather than moving the status
between buckets. Moving it would have fixed the anchor by breaking the verdict.

### Broken four times on purpose, and which guard caught which

A single test passes for both the bug and its mirror image, so the guards were
verified by mutation rather than by being green:

| break | what it simulates | guards that fire |
| --- | --- | --- |
| **A** — drop the skip branch | the original bug: a skip anchors | 2 |
| **B** — `PASSLIKE = ("pass",)` | the mirror image: skip reads as red | 4 |
| **C** — map advances on `PASSLIKE` | the bug re-admitted one level deeper | 1 |
| **D** — `parent_ran_job` moved above the call | fix present but **unreachable** | 1 |

**Break D initially fired ZERO guards**, and it is the most dangerous of the
four because the fix is still visibly in the file. The ordering assertion
matched the string `job_anchor` in the *block comment* above the call, so it
passed no matter where the call sat. It now anchors on the call itself. A guard
defeated by a comment is a failure this ticket family has already paid for
twice, and it was found only by running the mutation — not by reading the test.

### Verified against the real ledger, not only fixtures

- **Live state**: the synapse job is currently `fail` with no `job_last_pass`
  entry, so `job_anchor` returns `(None, "")` — no opinion, old behaviour
  preserved. Correct: the fix does not retroactively rewrite anything.
- **Counterfactual**, reconstructing the state as it stood at `c52fc389fd97`
  (the job carrying `skip`): `job_anchor` refuses with a reason, `range_for`
  returns `([], "")`. **The nine-commit range naming five innocent `lib/`
  and pin commits is not opened.**

### Gate

18 devtests covering the touched machinery (`diff_jobs`, `open_regressions`,
`job_tier`, `range_for`, `first_seen`, `last_covering_sha`, `PASSLIKE`,
`reg_open`, `orphan_keys`) — all green, including `devtest_skip_semantics.py`
and `twatch_first_seen_devtest.py`, the two nearest neighbours. Plus the new
`twatch_skip_anchor_devtest.py` (13 cases) and the reader-discipline guard.

The full 86-file devtest family was **not** run: plexus was at load 27 on 12
cores with the watcher mid-tier, and the box is the owner's workstation. The
covering subset is the risk surface; the family sweep is the ticket-filed
`chore-t-tools-devtest-is-one-job-that-runs-86-guards`, whose whole subject is
that this target costs 251s serial.

### Not fixed here, deliberately — the mirror residual

`reg_open`'s docstring already records it: a job going **red -> skip** counts
as FIXED and closes its regression, so *"a cascade whose jobs only ever SKIP
still closes wrongly."* That is the same `skip != pass` confusion pointing the
other way, and it is a **deliberate existing trade** — the alternative holds a
regression open forever on a box that cannot run the job. Changing it needs its
own decision about which failure is worse, and bundling it here would have
smuggled a policy change in behind a bug fix. Worth its own ticket if the false
"fixed" is ever observed to cost something.

### Where this sits

Fifth face of `bug-t-a-blame-range-is-computed-from-what-changed-not-from-what-
the-job-can-see` (in `done/`, closed under a table headed *"All four faces,
closed"*). `never_passed` is the sixth field of the family whose whole job is
to say *this range cannot mean what it appears to mean*, joining `first_seen`,
`pin_axis`, `pin_built`, `bad_untestable` and `no_testable_change`. No new
mechanism was needed, exactly as the triage predicted.

## Log
- 2026-08-28 — resolved, commit 0dec0194a.
