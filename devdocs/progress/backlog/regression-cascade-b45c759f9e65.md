---
prio: 70
---

# regression CASCADE: 15 jobs newly red at b45c759f9e65 (auto-filed by twatch)

- **Type:** regression cascade (auto-filed by Track T watcher, host borg).
  Untriaged. 15 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-07-31T13:19:29Z
- **Root-cause suspects in the red set:** none of the known root jobs — likely a broken build or harness event

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at b45c759f9e65ec3fee4f71ad1e2ef26f65618bb1

## Newly red jobs
- `test-c-conformance-arm32#shard2/6`
- `test-c-conformance-i386#shard0/6`
- `test-c-conformance-i386#shard1/6`
- `test-c-conformance-i386#shard2/6`
- `test-c-conformance-riscv32#shard0/6`
- `test-c-conformance-riscv32#shard1/6`
- `test-c-conformance-riscv32#shard2/6`
- `test-c-conformance-riscv32#shard3/6`
- `test-c-conformance-riscv32#shard4/6`
- `test-c-conformance-riscv32#shard5/6`
- `test-lua-cross#src:test/lua/runner.c`
- `test-sqlite-threads-aarch64#src:tools/run_sqlite_thread_test.sh`
- `test-sqlite-threads-arm32#src:tools/run_sqlite_thread_test.sh`
- `test-sqlite-threads-i386#src:tools/run_sqlite_thread_test.sh`
- `test-sqlite-threads-x86_64#src:tools/run_sqlite_thread_test.sh`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
