---
prio: 50
---

# bug: _Generic picks `int` where the operand is `long` on 32-bit targets

- **Type:** bug — **Track C (C frontend)**, filed by Track T
- **Found:** 2026-07-12, by newly enrolling the C cross-conformance matrix in
  testmgr's full tier ([[feature-testmgr-enroll-c-cross-conformance]])

## Symptom

`c-testsuite/00219.c` (a `_Generic` battery) fails on **i386, arm32 and riscv32**
— every 32-bit target — and passes on x86-64 and aarch64:

```
    @@ -6,7 +6,7 @@
     1
    -2
    +1
```

The failing selection is:

```c
i = _Generic(17L, int :1, long :2, long long : 3);   /* want 2, got 1 */
```

and the neighbouring `_Generic(i + 2L, long: "long", int: "int", ...)`.

## Diagnosis (hypothesis — Track C to confirm)

On ILP32 targets `int` and `long` are both 32 bits. C requires `_Generic` to
match on **type identity**, not representation: `17L` has type `long`, so the
`long:` association must win even though `int` has the same size and rank. PXX
appears to compare types by size/layout, so the `int:` association matches first.

On LP64 (x86-64, aarch64) `long` is 64-bit, the sizes differ, and the bug is
invisible — which is exactly why only the cross targets caught it.

## Repro

```
tools/testmgr.py --tier full --job 'test-c-conformance-i386#shard2/6'
# or the whole target, serially:
make test-c-conformance-i386
```

## Fix

Make `_Generic` association matching use type identity (distinguishing `int`,
`long`, `long long` even when they share a size/rank), not size-based
compatibility.

## Gate

`make test-c-conformance-{i386,arm32,riscv32}` green (00219.c passes), native
`test-c-conformance` stays green, plus C's usual gate.
