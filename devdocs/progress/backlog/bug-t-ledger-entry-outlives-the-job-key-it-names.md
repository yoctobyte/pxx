---
summary: "An open regression closes only when its job key reappears as FIXED, so an entry whose key vanishes — a renamed test, or an @N selector shift — can never close"
type: bug
track: T
prio: 55
---

# A ledger entry whose job key vanishes is immortal

- **Type:** bug (Track T — `tools/twatch.py`, the open-regression ledger)
- **Found:** 2026-08-04 by `claude@xeon`, triaging a NEW-RED that turned out to
  be a near-miss for this.

## The defect

`reg_open()` closes a per-job entry on exactly one condition:

```py
return r["job"] not in fixed
```

and `fixed` comes from `diff_jobs()`, which can only name keys the run actually
REPORTED. So if a job key stops existing, its entry can never be closed by any
future run: the key will never appear in `now`, therefore never in `fixed`.

This is the same shape as
[[task-t-borg-open-regression-is-permanently-stale]] — an entry nothing can
clear, sitting in the list agents are told to act on — but reached through the
job identity rather than the host.

## Two ways a key vanishes, both routine

1. **A test is renamed or deleted.** Ordinary lane work.
2. **The `@N` selector shifts.** `assign_selectors()` suffixes `@1`, `@2` … when
   one source is compiled more than once inside a target, and its docstring
   calls a change in that count "a far rarer event" than positional renumbering.
   It happened **twice in one night**: at `9df2717684` the Makefile carried
   `test/test_nilpy_print_arg_eval_order.npy` three times (an agent had
   overwritten an existing test with a same-named new one — `c8093ef11`,
   restored by `6d78481bb`), so the keys were `…npy@0/@1/@2`; once the
   duplicates went away the key reverted to the bare `…npy`. `xeon.json` still
   carries `…npy@1` and `…npy@2`, which no job can ever produce again.

Note 110 of xeon's job keys currently carry an `@N`, so the exposed surface is
not a corner case.

## The near-miss

`…npy@1` DID go NEW-RED at `9df2717684` (report
`20260804T050323Z-9df2717-xeon.md`) and the duplicate lines were removed in the
same window. No immortal entry was created — but only by luck: that run's
`parent_tested` equalled the tested sha, so the EMPTY RANGE rule recorded job
status without opening a ledger entry. Had the range been non-empty, the ledger
would now hold an entry for a job key that cannot be run.

## Fix shape

The machinery already exists — the ledger just does not use it. `st["jobs"]`
eviction distinguishes "this run could have run that job and didn't" from "not
my tier" via `job_tier` + `covered_tiers()`. Apply the same test in `reg_open`:
a per-job entry whose key is absent from a run that **covers its tier** names a
job no tier has any more, so close it as **GONE** rather than FIXED.

Two constraints, both learned from neighbouring bugs:

- Absence must be judged against tier coverage, never against a single run —
  the opt-jobs eviction bug (`optdiff#shard5/6` re-reporting NEW-RED forever)
  came from exactly that confusion.
- Closing must be VISIBLE, not silent: report it as `GONE: <key> — the job no
  longer exists in any tier`, the same discipline as the quiet-host hold. An
  entry disappearing quietly is indistinguishable from one being fixed, and the
  whole point of the ledger is that its entries are actionable.

Also worth considering, cheaply: a `skip`-only cascade close is already a known
residual in the same function; this fix touches the neighbouring lines and
should not silently widen it.

## Gate

`tools/testmgr.py --tier quick` green plus a devtest over `reg_open`: a key
still present and red stays open; a key present and passing closes as FIXED; a
key absent from a covering run closes as GONE; a key absent from a run that does
NOT cover its tier stays open.
