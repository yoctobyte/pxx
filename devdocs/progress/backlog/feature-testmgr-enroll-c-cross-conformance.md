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

## Done (Track T, 2026-07-12)

Enrolled in the `full` tier: `test-c-conformance-{i386,aarch64,arm32,riscv32}`
(each fanned out over the runner's 6 shards, like the native battery) and
`test-lua-cross`. +25 jobs, full tier 1157 -> 1182.

**The matrix is RED on arrival** — and these are real, confirmed independently of
testmgr (plain `make test-c-conformance-i386` fails the same way), so the ticket's
"all four green as of e0f9f5e4+" has regressed since:

- `00204.c` — struct-by-value/varargs truncated on **every 32-bit target**
  (i386/arm32/riscv32), fine on x86-64+aarch64 → [[bug-c-struct-byval-varargs-32bit]] (Track A, ABI)
- `00219.c` — `_Generic` picks `int` where the operand is `long`, again **32-bit
  only** (int and long are both 32 bits there, so type identity collapses)
  → [[bug-c-generic-long-vs-int-on-32bit]] (Track C)
- `00200.c` — left-shift promotion, **aarch64 only**
  → [[bug-c-lshift-promotion-aarch64]] (Track C/A)

So the watcher's full tier will report RED until those land. That is the honest
state and the whole point of enrolling — the matrix "found 3 real backend gaps on
day one" per this ticket, and it just did so again. Nothing gates dev pushes on
`full` (quick + self-host is the push bar), and tstate is the truth.
