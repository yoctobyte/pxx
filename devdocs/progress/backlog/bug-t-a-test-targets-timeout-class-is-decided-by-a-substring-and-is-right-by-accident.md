---
track: T
prio: 45
type: bug
status: backlog
blocked-by: []
found: 2026-08-29
found-by: frank-coordinator (measured), prompted by frankA
summary: "testmgr's classify() picks a job's timeout class by substring-matching the make -n recipe text. test-nilpy gets corpus/1200s because its recipe happens to contain 'sqlite', 'lua' and 'uforth' -- nothing about NilPy. Delete one test file and the whole suite silently drops to unit/90s, turning every slow-but-passing run into a false RED. uforth already fell through this exact hole."
---

# A target's timeout class is decided by a substring, and test-nilpy's is right by accident

## How it was found

frankA fixed a NilPy `range()` hang (`15afe4effd79`) and asked a good question:
*"worth checking whether testmgr's nilpy jobs have a per-job timeout at all — if
they do not, this test could wedge a tier instead of failing it."*

Measured rather than reasoned — `classify()` run over the actual
`make -n test-nilpy` recipe, 3268 lines:

```
class: corpus    timeout: 1200s
```

**So the answer to frankA's question is no, it cannot wedge a tier** — a hang is
killed and published RED at 20 minutes. That half is fine and needs no work.

The problem is *why* it lands there. `classify()` (`tools/testmgr.py`) is a
substring match over the recipe text, and test-nilpy hits the `corpus` arm
because its recipe contains **`sqlite`** (from `test_nilpy_sqlite_crud.npy`),
plus `lua` and `uforth`. Nothing about NilPy, its size, or its runtime put it
there.

## Why this is a bug and not a curiosity

**The trigger is a deletion anyone can perform while doing something else.**
Remove or rename `test_nilpy_sqlite_crud.npy` — a perfectly ordinary act — and
`test-nilpy` silently reclassifies from `corpus`/1200s to `unit`/**90s**. Every
slow-but-passing nilpy run then publishes a **false RED**, and nothing in the
tree connects the deletion to the consequence. The person doing the deleting
will be working on NilPy tests, not on the harness.

**This is a repeat, not a hypothesis.** testmgr's own source records uforth
falling through this exact hole:

> *"uforth is a corpus like the others, it just lives outside library_candidates
> ... so the path heuristic missed it and it fell through to `unit` — a 90s
> timeout. That was survivable at 46s; enrolling Gerry Jackson's 13 ANS word sets
> took the job past TEN MINUTES, so testmgr killed it and published a RED that was
> purely the harness misjudging the class."*

And the file already knows the general shape, in the `selfhost` arm:

> *"the job classes selfhost anyway, because `make -n` expands the $(COMPILER)
> prerequisite and THAT text contains compiler.pas. So the class is currently
> correct by accident of the prerequisite, not by anything about the script."*

That arm was then made correct **on purpose**. `test-nilpy` has had no such pass.

## The retry interaction, which frankA raised and which doubles the cost

`corpus` is in `RUN_RETRY_CLASSES`, so a job that genuinely hangs is retried
`RUN_RETRY_TRIES = 3` times: **3 x 1200 = 60 minutes** of a run's wall clock
before the failure is final. frankA's range hang would have done exactly that had
it been in a wired test. Retry is right for the classes it was designed for
(runtime-nondeterministic: qemu sockets, threaded sqlite, sharded conformance) —
test-nilpy is in that set for the same accidental reason it is in `corpus` at all.

## The fix, and explicitly not a checker

frankA's proposal, and it is the right shape: **an explicit per-target class map
for the handful of targets whose class actually matters, with the existing
heuristic as the fallback for everything else.** Roughly a dozen entries. A target
in the map is immune to recipe drift; everything else keeps today's behaviour.

**Not a checker.** Same argument as
`audit-a-a-comment-asserting-an-invariant-is-a-claim-about-a-sibling-arm-nobody-checked`:
a heuristic that flags "this class may be accidental" would fire on most of the
matrix and get scrolled past. The map is cheap, total for the cases that matter,
and self-documenting.

While in there, decide `test-nilpy`'s retry membership **deliberately** rather
than inheriting it from `corpus` — it is a deterministic build-and-run suite, and
`RUN_RETRY_CLASSES`' own comment says deterministic classes stay single-shot.

## Provenance note

frankA declined to file this itself (*"your call and your lane; I am not filing
into T"*) — correct: T owns the tool. Filed by the coordinator under its tooling
remit. The argument for filing despite the class being *currently right* is
frankA's and is worth preserving verbatim: **"currently right is exactly the
reason to file it rather than not"** — a correct-by-accident invariant with an
easy trigger and no written reason is the configuration that breaks silently.

## Gate

Track T's own, per its lane rules. Verify with short tiers and a scratch bare
repo; do not exercise this with long sweeps.
