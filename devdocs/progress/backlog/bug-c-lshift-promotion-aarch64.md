---
prio: 50
---

# bug: left-shift result type / integer promotion wrong on aarch64 (00200.c)

- **Type:** bug — **Track C (C frontend)**
- **Filed by:** the Track T watcher agent. Promotion semantics, so it starts in
  C; may turn out to be a codegen issue for the owning backend (see below).
- **Found:** 2026-07-12, by newly enrolling the C cross-conformance matrix in
  testmgr's full tier ([[feature-testmgr-enroll-c-cross-conformance]])

## Symptom

`c-testsuite/00200.c` exits 1 on **aarch64 only** (passes on x86-64, i386, arm32,
riscv32). The test checks the ISO C rule for `<<`:

> [6.5.7#3] "The integer promotions are performed on each of the operands. The
> type of the result is that of the promoted **left** operand."

It probes the *type* of `X << T(1)` for many combinations of X and shift-count
type T, via `sizeof` and signedness, and exits nonzero on the first mismatch.

## Why aarch64 alone is suspicious

The rule is target-independent, so a frontend that got the promotion wrong ought
to fail everywhere. Failing on exactly one target suggests either a
target-dependent type width feeding the promotion, or a codegen difference on
aarch64 (e.g. the shift narrowing/widening its operand). Whoever picks this up
should first find WHICH of the test's many CHECK() cases fires — the test prints
the failing expression.

## Repro

```
tools/testmgr.py --tier full --job 'test-c-conformance-aarch64#shard1/6'
# or the whole target, serially:
make test-c-conformance-aarch64
```

## Gate

`make test-c-conformance-aarch64` green (00200.c passes), other targets stay
green, plus the owning lane's usual gate.
