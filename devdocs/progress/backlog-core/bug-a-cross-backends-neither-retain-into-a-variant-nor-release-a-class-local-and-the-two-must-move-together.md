---
track: A
prio: 35
type: bug
blocked-by: []
summary: "arm32/riscv32/xtensa take NO PXXObjRetain when boxing an object into a variant, and none of the five cross arms of EmitManagedLocalCleanupForTarget releases a NilPy tyClass local at scope exit. The two errors cancel, so the observable today is bounded at one object per scope — but FIXING EITHER HALF ALONE turns that bounded leak into a use-after-free. They move together or not at all. Filed so the next person to 'add the missing retain' reads this first."
status: backlog
owner: frankS
---

# Cross backends: a missing retain and a missing release that cancel

- **Track A** (arm32 / riscv32 / xtensa variant boxing + the shared
  scope-exit cleanup). Measured 2026-08-31 by frankS while closing
  `feature-nilpy-object-reclamation`.
- **Low priority on purpose, and the priority is not the point** — the point is
  the coupling. The cost of getting this wrong is a UAF, not a leak.

## The two halves

**No retain.** `ir_codegen_arm32.inc`'s `IR_VAR_STORE` reaches the object case
through `VariantTagForTk` and fills the slot with no `PXXObjRetain`. riscv32 and
xtensa are the same shape; none of the three has a `VT_OBJECT` arm at all.
x86-64, aarch64 and i386 all retain (correctly, and only where the source does
not already own its `+1` — `IRNodeOwnsManagedObj`, added `ca8153b6c`).

**No release.** `EmitManagedLocalCleanupForTarget` (`ir_codegen.inc`) has five
cross arms — i386, arm32, aarch64, xtensa, riscv32 — and not one has a
`tyClass` case. Only `EmitManagedLocalCleanup` (x86-64, `symtab.inc:11209`)
drops a NilPy class binding's reference at scope exit.

## Why the observable is small, and why that is the trap

The LOOP case is already covered: the rebind ARC that releases a tyClass
local's old value is emitted at **IR level** (`ir.inc:10105`), which is
target-independent. So what the missing epilogue arm loses is the LAST value a
scope held — **one object per scope, not one per iteration.**

Measured on arm32, the one cross target NilPy builds for today
(`bug-a-nilpy-on-cross-targets-four-remaining-walls`):

| probe | 20k | 400k |
| --- | --- | --- |
| `x = Node(i)` in a loop | 8584 kB | 8584 kB |
| `o.w = Node(i)` into a variant field | 8548 kB | 8548 kB |
| `test_nilpy_object_in_variant_slot_survives_churn.npy` | prints CPython's own answer under `qemu-arm` | |

Flat, and correct. **That is the two errors cancelling, not two things working.**
A borrow stored into a variant slot is under-retained by exactly the amount the
never-released local over-holds.

## The failure this ticket exists to prevent

Add the `PXXObjRetain` to arm32's variant boxing and stop there: the slot now
holds `+1` it will release, the local still holds one nobody drops — a bounded
leak, no worse. Add the scope-exit `tyClass` release and stop there: the local's
reference is dropped while a variant slot holds the object **without ever having
retained it**, and the next read is a use-after-free. The second is the natural
first move, because "the epilogue is missing an arm" is the easier gap to see.

So: **both, in one commit, with a borrow-into-a-variant-then-drop probe run on
arm32 under qemu.** The x86-64 shape of that probe is in the scratch record of
`feature-nilpy-object-reclamation`; it is ~15 lines.
