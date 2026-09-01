---
track: A
prio: 50
type: bug
status: backlog
found: 2026-09-01
found-by: claude-T
owner: ""
blocked-by: []
summary: "CORRECTED 2026-09-01: the cause is DEAD-CODE ELIMINATION, not -O3, and the -O3 in this slug is the wrong description. Measured twice on different binaries: `-O0 --dce` SEGFAULTs with no optimiser involved, `-O3 --no-dce` passes, `-O3` hangs. So the named suspects d0537380a (rip-relative globals) and 44b256356 (PIE linking) are probably the WRONG bisect window -- -O3 merely turns DCE on, which is why five shards looked like an optimiser regression. Threading is incidental and the search must not be narrowed to threading code. Five optdiff shards share one job_last_pass and one signature; shard4 is a name collision and is tracked separately. frankZ holds it."
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

## CORRECTION 2026-09-01 — it is DCE, not -O3, and the bisect window is wrong

**The cause is dead-code elimination. The optimiser is not involved.** Found by
frankC, which had reached this ticket independently; measured again here on a
different binary before propagating, because the first version of this ticket
sent two sessions at the wrong commits.

Binary `1868e00dcfb0` at `215debee6`, `test/lib_criticalsection_blocking.pas`,
always with `--threadsafe`:

| flags | result |
| --- | --- |
| `-O0` | ok |
| `-O0 --dce` | **SEGFAULT (139)** |
| `-O3` | **HANG (124)** |
| `-O3 --no-dce` | **ok** |

`-O0 --dce` segfaults with no optimiser in the picture, and `-O3 --no-dce`
passes. That is dispositive in both directions: DCE is sufficient to break it
and removing DCE is sufficient to fix it at the level where it was first seen.

**So the suspects named above — `d0537380a` (rip-relative global operands) and
`44b256356` (PIE linking) — are probably the WRONG bisect window**, and the
`-O3` in this ticket's slug and title is the wrong description. The `-O3` HANG
and the `-O0 --dce` SEGFAULT are one bug wearing two faces; `-O3` merely turns
DCE on, which is why the whole block looked like an optimiser regression.

The slug is left alone deliberately: renaming a file another session is working
in is a merge conflict for no gain, and tstate/resolve citations key off it.
**Whoever closes this should rename it then.** The summary above is corrected,
because the summary is the part everyone reads.

**Threading is incidental, and that is now firmer, not weaker.** A whole-body
DCE defect would be observable wherever a body looks dead but is not; threaded
programs are where it happened to be caught. Do not narrow the search to
threading code.

Owner: frankZ holds this. The `owner:` field was EMPTY, which is what let frankC
reach it sideways from the v399 commit message and get a fair way in before
anyone noticed — a real collision, caught only because the human spotted two
sessions on "threading". Claim it.
