---
track: A
prio: 50
type: bug
status: backlog
found: 2026-09-01
found-by: claude-T
owner: ""
blocked-by: []
summary: "Six optdiff shards are red and it is NOT six problems. Five (shard0/1/2/3/5) share one signature and one job_last_pass (caa34fdeab46): a threading test that exits 0 at -O0 and TIMES OUT (rc 124) at -O3, one such test per shard, plus an `Illegal instruction` on shard1. shard4 is unrelated — older last_pass (6c88a2afc82b), an output divergence at -O1/-O2/-O3 with rc 0 vs 0, already tracked by regression-optdiff-shard4-12. The window after the shared last_pass holds only three buildable commits, two of which are x86-64 codegen: 44b256356 (PIE linking) and d0537380a (rip-relative global operands). HYPOTHESIS, not bisected."
---

# Five of the six red optdiff shards are one bug, not five

Filed because "six shards red" was being counted as six unknowns while sizing
the remaining pin-advisory reds. It is two, and one of those is already
ticketed.

## The five that are one thing

All from `devdocs/progress/tstate/seven.json` (`jobs`, `job_reason`,
`job_last_pass`):

| shard | failing program | signature |
|---|---|---|
| shard0/12 | `test_thread_api_no_uses.pas`, `test_threadsafe_heap_lock_release.pas` | `OPT DIFF -O3 … (rc 0 vs 124)` |
| shard1/12 | `test_threadsafe_layout_rtti.pas` | `OPT DIFF -O3 … (rc 0 vs 124)` + **`Illegal instruction`** |
| shard2/12 | `lib_criticalsection_blocking.pas` | `OPT DIFF -O3 … (rc 0 vs 124)` |
| shard3/12 | `lib_fpc_thread_surface.pas` | `OPT DIFF -O3 … (rc 0 vs 124)` |
| shard5/12 | `lib_classes_tthread.pas` | `OPT DIFF -O3 … (rc 0 vs 124)` |

Three things make this one bug rather than five:

1. **Identical `job_last_pass`: `caa34fdeab46`** for all five. They did not
   drift red independently; they went together.
2. **Identical signature.** `rc 0 vs 124` — 124 is `timeout`'s exit code. Every
   one exits 0 at `-O0` and **hangs** at `-O3`. Not wrong output; no output.
3. **Every failing program is a threading/locking test** — threads, critical
   sections, thread-safe heap and IO locks, `TThread`. Shards 6–11 pass and
   carry no threading programs in these positions.

`Illegal instruction` on shard1 is the same family seen from the other end: a
hang and a bad opcode are both what mis-generated code does, not what a
mis-written test does.

## shard4 is NOT part of it

| shard | failing program | signature | last_pass |
|---|---|---|---|
| shard4/12 | `test_threadsafe_io_lock_foreign.pas` | `-O1`, `-O2`, `-O3`, all `rc 0 vs 0` | `6c88a2afc82b` (2026-08-30) |

`rc 0 vs 0` is an **output divergence**, not a timeout; it fires at every
O-level rather than only `-O3`; and its last pass is two days older. Different
bug, already tracked as `regression-optdiff-shard4-12`. The name is confusingly
similar to the five above — that is the whole reason this ticket exists.

## Suspect window — three commits, two of them x86-64 codegen

`caa34fdeab46..297a6755c0bd` (the shared last pass to the run that observed the
reds) contains only three commits that touch a buildable file:

```
44b256356   8 files  feat(A): x86-64 objects link into a PIE, and the sibling arm …
d0537380a   9 files  feat(A): rip-relative global operands on x86-64, and the two …
3156ac887   1 file   docs(A): EmitGlobRef asserted a census that had already been …
```

PIE linking and rip-relative global addressing are exactly the surface that
would break thread-local and global access under optimisation while leaving
`-O0` intact — which is the observed shape.

**This is a hypothesis and has NOT been bisected.** Nobody has built either
commit's parent. It is offered as the place to start, not as a finding. Whoever
takes it: build under a compiler whose `srchash` matches the tree, and treat a
FAILURE under a mismatched binary as inconclusive — a stale binary can fake a
failure but cannot fake a pass.

## Why it is worth sizing correctly

These six are the largest block of the reds standing between the tree and a
`full` run with no RED tier — which is what `pin_is_green` requires, and
therefore what a fresh rollback target requires. Counted as six unknowns the
block looks like the dominant problem. It is one hypothesis plus one existing
ticket, and the `-O0`/`-O3` split means the reproduction is a single program and
two flags.

## Reproduce one directly

```
tools/testmgr.py --tier full --job 'optdiff#shard2/12'
```

or, faster, compile `test/lib_criticalsection_blocking.pas` at `-O0` and `-O3`
and run both; the `-O3` build should hang.

## Correction 2026-09-01 — the baseline amnesty is TEMPORARY, not permanent

The `chore(stable): pin v399` commit message says this defect "will stop
registering as new in `pin_shadow`" once `seed_baseline()` carries it into
v399's baseline. That is true only while the shards are still red, and the
unqualified wording invites the stronger reading. Correcting it here because a
commit message cannot be amended once pushed and this is where the defect lives.

`tools/twatch.py:2673`:

> *A baselined red that has since gone GREEN leaves the baseline for good, so a
> later re-break counts as new. Amnesty is for the reds that are still there,
> never a permanent pass for the job.*

So: while these five shards stay red they are `inherited` and do not colour the
pin grade. The moment they go green they drop out of the baseline permanently,
and any later re-break registers as new again. **Fixing this does not need a pin
or a baseline reset to become visible again — it self-cleans.**

Same mechanism retires the concern that `test-pascal-conformance#shard0/6` was
carried into v399's baseline because the pin was cut before a full tier could
re-measure it: shard0/6 is green, so it leaves the baseline on the next shadow
run without anyone doing anything.

Note also that under `fcbfc02f5` a pin is **graded, never gated** — so nothing
here is an argument against pinning at any point. It is a grade input.
