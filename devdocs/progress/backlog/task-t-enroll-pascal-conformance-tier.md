---
summary: "Enroll test-pascal-conformance in testmgr tiers (sharded, like the C battery)"
type: task
prio: 45
---

# Enroll the Pascal FPC-testsuite conformance battery in testmgr

- **Type:** task (Track T — tools & testing; owns testmgr tier composition)
- **Status:** backlog
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
