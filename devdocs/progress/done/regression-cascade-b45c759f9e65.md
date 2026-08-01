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

---

## Triage (2026-07-31, Track T)

Still red in all three full runs today (`b45c759`, `78847f9`, `6104264`) — the
same 15-job set, no drift.

**The c-conformance leg is explained and now split out** to
[[bug-c-main-missing-implicit-return-zero]]: `00211.c`'s `main` falls off the
end without a `return`, and the C frontend emits no implicit `return 0`, so the
exit status is stack garbage. It reported `exit=188`, `140`, `76` across the
three runs above — a genuine nondeterministic bug, not the flake it looks like.
That contradicts this ticket's "ONE root cause" framing for that leg, hence the
separate ticket; the split is deliberate.

**Still unexplained:** `test-sqlite-threads-*` (all four targets, x86-64
included) and `test-lua-cross`. The x86-64 sqlite-threads failure is the
interesting one — it rules out a purely cross-target/qemu explanation.

**Separately, a phantom episode worth recording:** at `8b98dc33c6b9` the full
tier reported NEW-RED for five unrelated core jobs (`test_class.pas`,
`cagg_init_local_b41.c`, `c_lua_opcode_decode_b132.c`,
`test_cross_param_2darray.pas`, `test_managed_store_via_addr_b279.pas`), all
FIXED at the next native run. Only four commits landed between — three
progress-docs edits and one `perf(nilpy)` change scoped to
`compiler/builtin/pylib.pas`, which cannot touch any of them. The `opt` tier at
that same sha was GREEN. That is a harness/build event, and it is the second
today. Tracked as Track T tooling work, not a compiler bug.

---

## CLOSED — the jobs are green (Track T, 2026-08-01)

Verified against live tstate at full-tier sha `832a0ad03776` (GREEN, 345.5s):
**every job this ticket names is passing, and xeon reports 0 failing jobs across
the whole 1637-job matrix.**

Closed as an auto-filed stub whose underlying failure is gone, not as work done
here. Left in `done/` rather than deleted so the signal history stays readable.

For the optdiff ones specifically: the compiler defect behind them was
[[bug-c-wide-string-literal-narrow-in-value-context]], and the reason there are
several tickets for one bug is
[[bug-t-optdiff-shard-identity-is-positional]] — the failure migrated shard
identity (5 -> 0 -> 2) as test files landed, re-filing itself each time. That
ticket is still open and is the thing worth fixing; these stubs are its symptom.

## Log
- 2026-08-01 — resolved, commit 832a0ad03.
