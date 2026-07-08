---
prio: 45
---

# testmgr: enroll the C cross-conformance matrix + lua-cross in the full tier

- **Type:** feature (test infra). Track T.
- **Filed:** 2026-07-08 by Track C while landing
  [[feature-c-cross-target-feature-coverage]] (T owns tools/testmgr.py, so
  filed rather than edited cross-lane).

## What landed (Track C side)
- `make test-c-conformance-{i386,aarch64,arm32,riscv32}` — the 220-program
  c-testsuite battery per cross target under QEMU
  (`tools/run_c_conformance.sh --target <arch>`, per-target skip files
  `test/c-conformance/pxx.skip.<arch>`). All four green as of e0f9f5e4+.
  ~1-3 min each serially; the runner still supports `--shard I/N` for fan-out
  (works combined with `--target`).
- `make test-lua-cross` — lua runner + script set on all four targets (green).

## Ask
Add these to the `full` tier in tools/testmgr.py (classify: conformance /
qemu / corpus as appropriate; the cross-conformance jobs are
qemu-per-program so probably `conformance` class with shard fan-out like the
native battery). Keeps the watcher catching per-target C regressions — the
matrix found 3 real backend gaps on day one (00120/00174-175/00189 tickets).
