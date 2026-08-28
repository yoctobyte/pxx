---
track: T
prio: 60
type: bug
blocked-by: []
summary: "PASSLIKE = (pass, skip), so a job that SKIPped because its corpus was absent counts as the last GOOD sha. When the corpus later appears and the job runs for the first time, the range is computed from a sha where it never executed — manufacturing a regression window full of innocent commits. Cost a real hypothesis and four wrongly-implicated commits on 2026-08-27."
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
