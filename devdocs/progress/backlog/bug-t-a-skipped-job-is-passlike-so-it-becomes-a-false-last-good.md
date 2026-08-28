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
