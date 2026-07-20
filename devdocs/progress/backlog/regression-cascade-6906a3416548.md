---
prio: 70
---

# regression CASCADE: 18 jobs newly red at 6906a3416548 (auto-filed by twatch)

- **Type:** regression cascade (auto-filed by Track T watcher, host borg).
  Untriaged. 18 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-07-20T20:45:48Z
- **Root-cause suspects in the red set:** none of the known root jobs — likely a broken build or harness event

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at 6906a3416548bb8b278512bb7afca1a534e1ee43

## Newly red jobs
- `test-c-conformance-riscv32#shard0/6`
- `test-c-conformance-riscv32#shard1/6`
- `test-c-conformance-riscv32#shard2/6`
- `test-c-conformance-riscv32#shard3/6`
- `test-c-conformance-riscv32#shard4/6`
- `test-c-conformance-riscv32#shard5/6`
- `test-lua-cross#src:test/lua/runner.c`
- `test-riscv32#src:test/ccross_args.c@1`
- `test-riscv32#src:test/ccross_args.c@2`
- `test-riscv32#src:test/ccross_double_to_int.c@1`
- `test-riscv32#src:test/ccross_double_to_int.c@2`
- `test-riscv32#src:test/ccross_entry.c@1`
- `test-riscv32#src:test/ccross_entry.c@2`
- `test-riscv32#src:test/cunsigned_div_mod_b123.c@1`
- `test-riscv32#src:test/cunsigned_int_arith_b121.c@1`
- `test-riscv32#src:test/cunsigned_int_arith_b121.c@2`
- `test-riscv32#src:test/cunsigned_semantics_sweep_b138.c@1`
- `test-riscv32#src:test/cunsigned_semantics_sweep_b138.c@2`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
