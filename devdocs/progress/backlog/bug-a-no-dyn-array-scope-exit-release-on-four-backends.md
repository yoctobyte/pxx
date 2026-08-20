---
track: A
prio: 40
type: bug
blocked-by: []
summary: "Only x86-64 releases a local DYNAMIC array at scope exit. i386, arm32, aarch64 and riscv32 have no `ArrLen = -1` arm in EmitProcEpilog at all, so every local dyn array leaks its block and its managed elements on those four targets. Measured with the interface-container repro: x86-64 destroys 2, aarch64 and i386 destroy 0."
status: backlog
owner: unassigned
---

# Four backends never release a local dynamic array at scope exit

- **Track A** (`compiler/symtab.inc`, the four per-target `EmitProcEpilog` arms).
- Found 2026-08-21 by running the interface-container family's repro across
  targets after fixing it on x86-64.

## Measured

`grep -n 'ArrLen = -1' compiler/symtab.inc` finds exactly ONE scope-exit release
site, and it is inside x86-64's `EmitManagedLocalCleanup`. The i386, arm32,
aarch64 and riscv32 epilogues have no dynamic-array arm at all — they carry the
COM-interface arm, the static-array arm and the scalar string arm, and stop.

Same program, `LocalDyn` filling a local `array of IFoo` with two objects and
returning:

| target | destroyed at scope exit |
| --- | --- |
| x86-64 | **2** (correct — matches FPC) |
| aarch64 | 0 |
| i386 | 0 |

The interface elements make it *observable*; the underlying leak is not
interface-specific. A local `array of string`, `array of TManagedRec` or a plain
`array of Integer` leaks its block on those four targets just the same, because
nothing releases the allocation.

## Why it stayed invisible

Cross-target tests assert printed OUTPUT, and a leak prints nothing. The x86-64
arm has been there long enough that the shape reads as covered; the divergence
only surfaces when a test makes destruction observable, which is exactly what
`test/test_interface_containers.pas` now does — though it runs native-only
today, so it does not catch this either.

## Shape of the fix

Each of the four epilogues needs the arm x86-64 has:

```pascal
else if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
  <load the slot>; PXXDynArrayRelease(data, desc)
```

with the target's own argument-passing. `GetOrAllocSymRTTI` already builds the
descriptor target-independently, and `PXXDynArrayRelease` is plain Pascal, so
there is nothing new to design — this is four mechanical arms plus the
`ManagedElemKindLocked` question below.

**Note the lock question is NOT the same on those targets.** x86-64 wraps the
call in `EmitAcquireHeapLock`, which is why `ManagedElemKindLocked` refuses
interface elements under `--threadsafe`. The other backends do not use that
codegen spinlock at all, so whether their arm should be locked, softlocked or
unlocked has to be answered rather than copied. If in doubt, mirror x86-64's
gate and file the difference — a leak under an opt-in flag is recoverable, a
deadlock is not.

## The deeper reading

Five hand-written copies of one epilogue is why half of them are missing an arm
each. `refactor-a-the-missing-layer-between-frontends-and-backends` is where
that gets solved properly; this ticket is the interim correctness fix, and
whoever takes the refactor should read the five arms first — the diffs between
them ARE the bug list.

## Gate

The interface-container repro run under each target's emulator destroys the same
counts x86-64 does; self-host fixedpoint; `tools/gate.sh quick`.
