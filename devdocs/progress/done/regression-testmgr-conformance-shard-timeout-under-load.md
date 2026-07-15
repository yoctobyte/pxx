---
prio: 60
---

# Track T: c-conformance shards time out under full parallel load (false REDs)

- **Track:** T (test infra)
- **Found:** 2026-07-13, during a Track A/C session — it produced THREE false REDs in one
  night and cost several full-matrix reruns.

## Symptom

`tools/testmgr.py --tier full` intermittently reports

```
  FAIL     test-c-conformance-arm32#shard3/6   conformance   39.7s  tools/run_c_conformance.sh
  FAIL     test-c-conformance-aarch64#shard3/6 conformance   44.5s  tools/run_c_conformance.sh
```

and the same job run on its own passes in **8.2 s**:

```
tools/testmgr.py --tier full --job 'test-c-conformance-arm32#shard3/6'
  PASS ... 8.2s
```

So the shard takes ~5x longer under the full 16-way parallel matrix than alone, and
crosses the timeout. `#shard3` is the usual victim; `test-aarch64#…sysopen` and
`test-c-conformance-aarch64#shard1` have flaked the same way (exit=124).

## Not a compiler regression — verified

Suspecting my own change (anonymous bit-fields, which stops those structs being opaque and
so does MORE layout work), I timed the same shard with the PINNED pre-change compiler:
**8.2 s, identical**. The slowdown is contention, not codegen.

## Why it matters

A false RED is worse than a slow test: it burns a full-matrix rerun (~5 min each), and it
trains the reader to shrug at REDs — exactly the reflex that lets a real regression through.
Three of four full runs went RED this way tonight.

## Suggested fixes (Track T's call)

- Scale the per-job timeout by the concurrency actually in flight, or give the conformance
  jobs (which fork 220 compiles + 220 qemu runs each) a larger budget than a unit test.
- Or lower the parallel cap for the conformance family specifically — they are already
  internally parallel, so stacking 6 shards x N targets against 16 slots oversubscribes.
- Either way, distinguish TIMEOUT from FAIL in the report. `exit=124` currently reads
  exactly like a wrong-output failure, and the log tail shows a successful build followed
  by nothing, which is genuinely ambiguous (that ambiguity already cost one bogus
  regression ticket: regression-test-aarch64-test-cross-sysopen-family).

## Log
- 2026-07-15 — resolved, commit ab3a5b2a.
