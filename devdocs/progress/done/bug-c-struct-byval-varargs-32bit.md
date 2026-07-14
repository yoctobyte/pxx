---
prio: 50
---

# bug: struct-by-value / varargs args truncated on 32-bit targets (00204.c)

- **Type:** bug — **Track A (backend / ABI)**
- **Filed by:** the Track T watcher agent
- **Found:** 2026-07-12, by newly enrolling the C cross-conformance matrix in
  testmgr's full tier ([[feature-testmgr-enroll-c-cross-conformance]])

## Symptom

`c-testsuite/00204.c` fails on **i386, arm32 and riscv32** — every 32-bit target
— and passes on x86-64 and aarch64. The test passes structs of every size 1..N
by value (and through varargs); output stops early, so the larger structs are
not arriving intact:

```
     abcd
     abcd0000
    -abcd00000000
    -abcd000000000000
```

(The last two expected lines are simply missing from our output.)

The test's own header says it targets calling-convention corners:

```c
// This program is designed to test some arm64-specific things, such as the
// calling convention, but should give the same results on any architecture.
```

## Diagnosis (hypothesis — Track A to confirm)

Struct-by-value passing (and/or the varargs path) for structs larger than one
register on the 32-bit ABIs. The natural suspects are the register/stack split
for multi-word structs and the alignment rules that differ between the 64-bit
ABIs (which pass) and the 32-bit ones (which don't).

## Repro

```
tools/testmgr.py --tier full --job 'test-c-conformance-i386#shard5/6'
# or the whole target, serially:
make test-c-conformance-i386
```

## Gate

`make test-c-conformance-{i386,arm32,riscv32}` green (00204.c passes), plus A's
usual gate: `make test` + self-host fixedpoint byte-identical + cross.

## 2026-07-14 — NOT REPRODUCIBLE. Closing as stale (fixed by other work).

Compiled `c-testsuite/00204.c` for **i386, arm32, riscv32 and aarch64** and diffed each
run against `00204.c.expected`: **all four match, byte-identical, full output** — no
truncated tail. The ticket's own repro is green on every target it names.

No commit is credited because none was aimed at this: it fell out of the 32-bit variadic /
struct-by-pointer ABI work (the `v178` variadic ABI arc and the 32-bit heap/PWord fixes).
Closed as not-reproducible rather than fixed.

## Log
- 2026-07-14 — resolved, commit 20e1232c.
