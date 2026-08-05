---
prio: 70
---

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 15 jobs newly red at aba953cae031 (auto-filed by twatch)

- **Type:** regression cascade (auto-filed by Track T watcher, host plexus).
  Untriaged. 15 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-05T20:35:05Z
- **Root-cause suspects in the red set:** none of the known root jobs — likely a broken build or harness event

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at aba953cae03106e2b53a0ef178d85489062c08c1

## Newly red jobs
- `test-riscv32#src:test/lib_bignum_ops.pas`
- `test-riscv32#src:test/test_array_of_const_types.pas`
- `test-riscv32#src:test/test_async_sl.pas`
- `test-riscv32#src:test/test_collections.pas`
- `test-riscv32#src:test/test_conformance_2.pas`
- `test-riscv32#src:test/test_cross_write_pchar.pas`
- `test-riscv32#src:test/test_ctor_string_literal_arg.pas`
- `test-riscv32#src:test/test_dynarray_copy.pas`
- `test-riscv32#src:test/test_inline_expand.pas@1`
- `test-riscv32#src:test/test_inline_expand.pas@2`
- `test-riscv32#src:test/test_overflow_checks_qplus.pas`
- `test-riscv32#src:test/test_overflow_qplus_narrow.pas`
- `test-riscv32#src:test/test_signal_default_revert_b336.pas`
- `test-riscv32#src:test/test_signal_handler_callback_b336.pas`
- `test-riscv32#src:test/test_stackless_gen.pas`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
