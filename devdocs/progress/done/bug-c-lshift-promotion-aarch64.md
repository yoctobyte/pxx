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


## RESOLVED 2026-07-13 — duplicate of [[bug-c-unary-minus-no-integer-promotion]]

Filed by the Track T watcher from the failing job (00200.c on aarch64); fixed the same day
from the failing test.

The ticket guessed left-shift promotion. It was NOT the shift: it was **unary minus**.
`00200.c` detects operand signedness with `(M) < 0 || -(M) < 0`, and cparser copied the
operand's type onto the AN_NEG node — so `-(unsigned short)1` stayed UNSIGNED and the
compare was an unsigned compare, false for every value. The integer promotions make it a
signed int -1. Unary `~` already promoted correctly; `-` was the sibling that never did.

Worth recording because the ticket's own hypothesis was wrong and the shift path was fine:
the arithmetic was never wrong (`-(us)` still printed -1), only the TYPE was, which is why
it read as a shift/codegen problem from the job report.

Verified: `test-c-conformance-aarch64#shard1/6` PASSES. Regression:
`test/cunary_minus_promote_b253.c`.
