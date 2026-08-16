---
summary: "Enroll test-pascal-conformance in testmgr tiers (sharded, like the C battery)"
type: task
prio: 45
---

# Enroll the Pascal FPC-testsuite conformance battery in testmgr

- **Type:** task (Track T — tools & testing; owns testmgr tier composition)
- **Status:** done
- **Opened:** 2026-07-14
- **Filed by:** Track B after the conformance burn-down (293 pass / 0 fail /
  223 skip / 34 auto-gated of 550 curated).

## The asymmetry

`test-c-conformance` runs in the `limited` and `full` tiers (native, plus
per-target under qemu in `full`). The Pascal analog —
`tools/run_pascal_conformance.sh`, same contract, same skip-list model
(`test/pascal-conformance/pxx.skip`) — is enrolled NOWHERE. It runs only when
someone types it, so a frontend regression that breaks a passing conformance
test is invisible to the watcher until a human re-runs the sweep by hand.

Today it is at **0 fail**, which is exactly when enrolling is cheap: any new
red is a real regression, no baseline noise.

## Scope

- Add a `test-pascal-conformance` job to the `full` tier (native x86-64 only —
  no cross variants; the suite tests the frontend, not the backends).
- Shard it like the C battery: the script already supports `--shard I/N`
  (`CONFORMANCE_SHARDS` machinery in testmgr should generalize or get a
  sibling). Whole battery ≈ 550 programs, wall-time pole as one job.
- Job class `conformance` (est_mem/timeout already modeled).
- Suite lives in `library_candidates/fpc-testsuite` (gitignored, fetched via
  `tools/install_lib_candidates.sh fpc-testsuite`); the runner already exits 0
  with a SKIP notice when absent, so boxes without the suite stay green —
  mirror whatever the c-testsuite jobs do about "say it loudly" (testmgr
  already warns about missing c-testsuite; extend that warning).

## Done when

A pxx frontend regression that flips a passing FPC-conformance test shows up
as a tstate NEW-RED tied to the offending SHA, with no human running the
sweep manually.

## Scope, decided by the user 2026-08-14 — x86-64 native ONLY

> *"Our compliance test just goes to PC platforms, and preferably only 64-bit.
> We are not going into historic compliance — that just doesn't make sense."*

FPC supports the ESP32 family too, so its suite carries its own truckload of
target `{$ifdef}`s. Chasing those would mean conforming to *FPC's embedded
decisions* rather than to Pascal, which is not what parity is for.

**So when this is enrolled: native x86-64 only. Do NOT add
`test-pascal-conformance-i386` / `-aarch64` / `-arm32` / `-riscv32` shards**, the
way `test-c-conformance` has them. That mirroring would look like consistency and
would be the wrong call here.

Already true in practice, which is why this is a scope note rather than work:
`tools/run_pascal_conformance.sh` states that *"tests gated on other
CPUs/targets/FPC-versions or needing suite infra we don't model are auto-skipped
and counted separately from the curated skip list"*, and it runs against
`compiler/pascal26`. The risk is drift at enrolment time, not today.

Related: [[decide-may-uses-math-cost-the-heap-and-exception-runtime]] settled the
same question one level down — FPC parity is opt-in behind `--strict-fpc`
because FPC's choices (unmasking the FPU, raising from `math`) are policy, not
Pascal, and are actively wrong on embedded targets.

## 2026-08-14 — ENROLLED, sharded 6-way, x86-64 native only

`test-pascal-conformance#shard0/6 .. #shard5/6` are in `TIERS["full"]`, class
`conformance`, honouring the user's scope decision above: **no cross shards.**

### It is not a Makefile target, deliberately

Built like `optdiff` — `Job()`s constructed directly in `generate()` — rather
than behind a new `test-pascal-conformance:` recipe. The recipe would be one
line invoking a script that already exists, and the Makefile is not Track T's
ground; this is the same call [[task-t-enroll-libtest-demos-watcher]] made when
it left `demos` alone. Both invocation styles already exist in the tree
(`run_c_conformance.sh` via make, `optdiff.sh` direct), so this adds no new
mechanism.

### The suite path is named explicitly, and that is load-bearing

The job line passes `library_candidates/fpc-testsuite/tests/test` rather than
letting the script fall back to its own default, so `CORPUS_RE` sees the tree
and the job **self-skips** on a box that has not fetched it. Left implicit, the
script prints its own `SKIP — no suite at ...` and exits 0 — a silent green for
550 programs that never ran, which is precisely the c-testsuite failure mode
`CORPUS_ROOTS` exists to prevent. Confirmed on a clone without the suite: 6 jobs
skip and the corpus banner names `library_candidates/fpc-testsuite`.

### `classify()` now matches the conformance FAMILY, not one script name

It tested `"run_c_conformance" in text`. A Pascal battery would have classed
`unit` — a 90 s timeout for a 550-program sweep, so testmgr would have killed it
and published the kill as a RED. Now `re.search(r"run_[a-z0-9]+_conformance")`,
per `normalise-dont-special-case.md`: the next frontend's battery is classed
right before anyone notices. Verified inert — 0 of 5528 existing jobs change
class.

### A latent testmgr bug this surfaced: the compiler snapshot was not layout-complete

Worth recording, because the symptom was indistinguishable from a frontend
regression and cost the first two runs. `RUN_COMPILER` copied the compiler to a
FLAT `/tmp/testmgr-scratch-N/pascal26`. The compiler resolves units against
`ExeDir` — its own directory — needing `ExeDir/builtin/` for the builtin units
and `ExeDir/../lib/rtl` for the RTL; a flat copy has neither. It worked anyway
only through `parser.inc`'s CWD-relative fallback, because every job's script
starts `cd REPO`.

That contract holds exactly as long as a job keeps the repo root as its CWD —
and a conformance runner compiles from **inside the suite directory**. Measured:
25 of shard 0's 92 programs FAIL with

```
pascal26:N: error: uses: unit source not found: builtinheap
```

which reads like a frontend regression and is entirely the harness. The same
shard run against an in-repo compiler was **0 fail**.

Fixed generally rather than worked around for this one job: the snapshot now
mirrors the repo's shape — binary in `<scratch>/compiler/`, with `builtin/`
beside it and `lib/` one level up, both symlinked to the real trees. Both links
are required; each alone still fails, and the builtin-only case fails with a
*warning* plus `undefined variable (IntToStr)` rather than anything naming a
search path. The symlinks pin no sources — the snapshot never did, jobs already
compile against the live tree — they preserve exactly its one guarantee, that
the compiler BYTES survive a concurrent rebuild. Teardown is `shutil.rmtree` in
every path, which unlinks a symlink instead of recursing through it, so `lib/`
is not reachable from cleanup.

### Measured: 4 of 6 shards green, and the 2 reds are a REAL regression

```
  PASS  test-pascal-conformance#shard0/6   27.8s
  PASS  test-pascal-conformance#shard1/6   27.8s
  FAIL  test-pascal-conformance#shard2/6   18.6s   tgeneric72.pp(compile)
  FAIL  test-pascal-conformance#shard3/6   20.7s   tclass13b.pp(compile)
  PASS  test-pascal-conformance#shard4/6   26.2s
  PASS  test-pascal-conformance#shard5/6   24.1s
```

Both reproduce with a plain in-repo compiler outside testmgr, so they are not
harness artefacts. Both are one Pascal-frontend defect, filed into the owning
lane per *T owns the tool, never the bug*:
[[bug-a-duplicate-class-name-check-is-scope-blind]] — the duplicate-class-name
check added in `1c24510b3` (2026-07-30) uses a flat per-unit namespace, so a
nested class name legally reused under a different enclosing class, or
materialized once per specialization of an outer generic, reads as a
redeclaration. Reduced to two 10-line repros in that ticket.

**This ticket's "Done when" is met on day one**: a frontend regression that
flipped a passing conformance test is now visible without a human running the
sweep. It had been invisible for **4480 commits** — the battery was at 0 fail at
its burn-down and is at 2 fail today, and nothing observed the transition. That
is the entire argument for enrolling, demonstrated by the enrolment itself.

### Known cost, stated plainly

Shards 2 and 3 publish RED until that Pascal fix lands, and **a red shard cannot
report a further regression** — the other ~90 programs in each lose their
NEW-RED signal meanwhile. Enrolled anyway, because the alternative is that all
six stay invisible and the reds are true rather than manufactured (the
distinction that held `lib-test` back was a *fake* red blaming pxx for a broken
gcc oracle). The cheap restore, if the frontend fix is not near, is two
`test/pascal-conformance/pxx.skip` entries referencing the bug ticket — that
file belongs to the owning lane, not to T, so it is noted there rather than
committed here.

Expect twatch to also file its own per-job `regression-*` stubs for these two on
the first full run; `already_filed` dedupes by slug, and a hand-written
diagnosis ticket has a different slug, so the stubs are additive noise, not a
conflict.

### Gate: sampled, not a full tier — and why

T's stated gate is `--tier full` green. That was not run, and claiming it would
be false: `full` is 2560 jobs, plexus was running the live watcher's own full
tier throughout (testmgr's co-tenancy notice fired on every run below), and a
native-tier attempt managed 21 of 1236 jobs in twelve minutes under that load
before being stopped rather than starve the watcher for hours. Per this track's
own rule — *test the tooling with QUICK tiers, never long runs* — the snapshot
change was verified by sampling every job CLASS it could plausibly break:

| class | sample | result |
| --- | --- | --- |
| selfhost | `selfhost-fixedpoint#00`, `fpc-bootstrap#00` | pass |
| unit | `--tier quick` (15), `test-core#1?` (10), `test-nilpy#10?` (10) | 35/35 pass |
| qemu | `test-i386#1?` (10) | 10/10 pass |
| corpus | the 2 `lib-test` corpus jobs | pass (as skip, corpus absent) |
| conformance | all 6 pascal shards | 4 pass, 2 red on the frontend bug |

`selfhost-fixedpoint` is the one that matters most: it builds the compiler with
the snapshot and demands byte-identity, so it exercises the moved path harder
than anything else in the tier. `full` on an idle box remains the real proof,
and the watcher will supply it on its next full cycle — testmgr is re-executed
per cycle rather than held in memory, so this needs **no twatch restart**.

## Log
- 2026-08-16 — resolved, commit c7d8d1f54.
