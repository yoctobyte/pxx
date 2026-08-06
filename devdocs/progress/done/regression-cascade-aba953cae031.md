---
prio: 70
status: done
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


## Triaged and fixed 2026-08-06 — one root cause, mine

All 15 jobs, one cause, and it was not a harness event as the auto-file guessed.

    pascal26:763: error: target riscv32: unsupported node in IR codegen: atomic

`fc75ba020` (InterLocked* resolve with no `uses`) put the InterLocked family in
`compiler/builtin/builtin.pas` — the builtin unit **every program pulls**. Their
bodies emit an atomic IR node, and riscv32 has no `IR_ATOMIC` arm. So the
failure landed on 15 riscv32 programs that never mention atomics: the error is
not "InterLocked is missing", it is the builtin unit failing to compile at all.

I guarded that block on `PXX_ESP` and, for the 64-bit peers, `CPU64`. Both
guards were reasoned, not measured, and neither covers plain
`--target=riscv32`: it is not the ESP platform and the 32-bit entries survive
`CPU64`. Measured properly now — `IR_ATOMIC` occurrences per backend:

    x86-64  1     i386  2     arm32  3     aarch64  3
    riscv32 0     xtensa 0

So the guard is now on the **backend capability** (`CPURISCV32` / `CPUXTENSA`),
which is the actual precondition, rather than on the platform that happened to
surface it first. Xtensa was only covered before because ESP implies it;
`--target=xtensa` without the ESP profile had the same hole.

Verified: all 14 named jobs green again, x86-64 InterLocked unchanged
(`test_interlocked_no_uses` passes), self-host fixedpoint converged.

Lifting the guard properly — giving riscv32 and xtensa real atomic codegen — is
[[bug-a-riscv32-and-xtensa-have-no-atomic-codegen]], which I filed the same
night **without noticing it had turned 15 green jobs red**. That is the
miss worth recording: I read the cascade as a pre-existing target gap because a
ticket for the gap existed, instead of asking why previously-green jobs changed.

**Resolved:** PENDING-COMMIT

## Log
- 2026-08-06 — resolved, commit 6532d45ac.
