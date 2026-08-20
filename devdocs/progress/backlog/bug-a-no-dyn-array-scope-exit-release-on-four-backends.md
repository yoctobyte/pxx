---
track: A
prio: 40
type: bug
blocked-by: [bug-a-i386-and-aarch64-dynamic-array-assignment-has-no-store-arm]
summary: "Only x86-64 released a local DYNAMIC array at scope exit; the other four backends had no `ArrLen = -1` arm at all. HALF DONE 2026-08-21: arm32 and riscv32 now release (measured flat, 112 MB -> 7.8 MB over 200k calls). i386 and aarch64 are BLOCKED — their IR_STORE_SYM has no dyn-array arm, so `b := a` aliases without retaining and the release would be a double free."
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


## 2026-08-21 — HALF LANDED (Track A), and the other half found its blocker

**arm32 and riscv32: done.** Both grew the arm x86-64 has, emitted UNLOCKED
(neither backend uses the codegen BSS spinlock, so there is nothing to hold and
`ManagedElemKindLocked`'s ThreadSafeMode refusal does not apply to them).
Measured, 200k calls of a routine with a local 8-element `array of string`:

| | before | after |
| --- | --- | --- |
| arm32 | 112 MB | **7.8 MB** |
| riscv32 | 112 MB | **7.7 MB** |

(~7 MB is the emulator's own floor; the shape is flat, not linear.) And
`test/test_interface_containers.pas` now reports `dyn: 2` on both, matching FPC
and x86-64 instead of 0.

**i386 and aarch64: reverted, and the reason is the finding.** Adding the
release to those two turned a silent leak into memory corruption, because
neither backend's `IR_STORE_SYM` has a whole-dynamic-array arm: `b := a`
aliases the handle WITHOUT retaining it, so releasing both at scope exit
double-frees. aarch64 SIGSEGVs on the second call of such a routine; i386
double-decrements a freed refcount word and carries on. On aarch64 there is a
second layer — `IR_STORE_SYM` tests `TypeKind = tyAnsiString` first, and an
array's TypeKind IS its element kind, so `array of string` is routed through the
scalar string store as well.

That is filed as
[[bug-a-i386-and-aarch64-dynamic-array-assignment-has-no-store-arm]] and this
ticket is now `blocked-by:` it. **Order matters**: retain first, release second.
The reverse lands a double free, which is exactly what was measured today.

arm32 and riscv32 were safe precisely because they already grew that store arm
(`bug-a-arm32-dynamic-array-assignment-has-no-store-arm`) — so the split is not
arbitrary, it follows the retain/release pairing, and it was measured per target
rather than assumed.

**Still out of scope: xtensa.** Its epilogue has neither a dyn-array arm nor a
static-array one; it is ESP-class and gets its own pass, not a copy of this one.

## What the five-copy epilogue cost, concretely

This ticket, [[bug-a-local-dynamic-array-of-string-is-released-as-a-string-handle]]
and the one above are all the same shape: five hand-written copies of one
epilogue, each missing a different arm, each divergence invisible because a leak
prints nothing. The audit that finds the rest is to diff the five arm-lists
against each other — the differences ARE the bug list — and
[[refactor-a-the-missing-layer-between-frontends-and-backends]] is where that
stops recurring.
