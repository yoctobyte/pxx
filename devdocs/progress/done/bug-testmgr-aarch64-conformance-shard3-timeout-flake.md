---
summary: "test-c-conformance-aarch64#shard3 00040.c times out (exit 124) under full parallel load; passes standalone — recurring flake"
type: bug
prio: 35
track: T
---

# testmgr flake: aarch64 c-conformance shard3 (00040.c) exit-124 under full load

- **Type:** bug (test infra — flaky timeout). **Track T** (testmgr tiers /
  timeout margins).
- **Status:** done
- **Opened:** 2026-07-14 (night session).

## Evidence

Three occurrences on the same box (full tier, ~16-way parallel):

- b310's gate (2026-07-13, noted in 603cf2bd's commit message): shard3 timed
  out twice under load, 8.2s standalone, pinned pre-change compiler identical.
- 2026-07-14 night, full run for fec98091: `00040.c — exit code 124 (want 0)`,
  PASS standalone in 14.7s.
- 2026-07-14 night, full run for 30eb98f0: same signature, PASS standalone.

Always the same shard, same test, only under full parallel load, never a
wrong RESULT — a qemu-user process starved past the per-test timeout.

## Suggested fixes (T's call)

- Scale the per-test timeout for qemu conformance jobs with the load factor
  testmgr already computes (it scales scheduling; the per-test kill timer
  apparently not), or
- give cross-conformance shards a lower parallelism class, or
- one automatic retry for exit-124 within a conformance shard (a timeout is
  load-shaped, not result-shaped, so a retry cannot mask a real failure that
  reproduces).

## Impact

Every full-tier run on a loaded box has ~⅓ chance of a spurious RED, which
costs a manual standalone rerun to dismiss — tonight it did so twice.

## Log
- 2026-07-15 — resolved, commit ab3a5b2a.
