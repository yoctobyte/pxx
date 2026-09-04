---
track: A
prio: 35
type: bug
blocked-by: []
summary: "FIXED: arm32/riscv32/xtensa now take the guarded PXXObjRetain when boxing an object into a variant, and all five cross arms of EmitManagedLocalCleanupForTarget release a NilPy tyClass local at scope exit -- both in one commit, because either alone turns a bounded leak into a use-after-free. Measured with a TWO-slot borrow probe (one slot cannot see past the cancellation): arm32 SIGSEGV -> correct, i386/aarch64 live=39955 -> live=9."
status: done
owner: frankb-78
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

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## Resolved — both halves, one commit, measured on four targets

**The probe.** `test/test_nilpy_variant_borrow_two_slots.npy`: TWO variant slots
borrowing ONE local instance, then one of the two borrows dropped and the other
read. The second slot is the whole point — with ONE slot the two errors cancel
*exactly*, so a one-slot probe is green before and after and guards nothing.
This ticket's own "measured on arm32, flat and correct" table is that: it is the
cancellation, correctly described, and a one-slot instrument cannot see past it.

**Positive control, drawn from the population, run before the fix** (pin v403,
`ce63beeeb`):

| target | before | after |
| --- | --- | --- |
| x86-64 | correct, `live=9` | unchanged (this commit does not touch it) |
| arm32 (neither half) | **SIGSEGV** | correct, `live=9` |
| i386 (retain, no release) | correct, **`live=39955`** | correct, `live=9` |
| aarch64 (retain, no release) | correct, **`live=39955`** | correct, `live=9` |

`allocs=208613` in every column, so the census is comparing the same work. The
two rows measure DIFFERENT halves and neither could have found the other: the
value assertion sees the missing retain (a dangling read), and only the census
sees the missing release (a leak prints nothing). Both rows are wired on all
four targets.

**riscv32 and xtensa got the retain and cannot be probed from NilPy** — `class`
refuses to compile for either ("a heap arena needs mmap"), so the code landed
with its siblings rather than leaving the three 32-bit backends to drift again.
Said here rather than left for a reader to assume it was tested.

**What the change is.** Retain: a `tyClass` arm asking `IRNodeOwnsManagedObj` in
`EmitVariantPayload{RISCV32,Xtensa}` and in arm32's `IR_VAR_STORE` /
`IR_VAR_BOX`, with an `EmitObjRetain{Arm32,RISCV32,Xtensa}` beside each file's
existing string-incref twin. Release: a `tyClass` arm in all five cross arms of
`EmitManagedLocalCleanupForTarget`, predicate copied from x86-64's
(`NilPyUserCode and PyClassSymArcEligible(i)`), loading the instance
POINTER-WIDTH from the slot.

**One thing the release arm needed that was not there.** x86-64's twin opens
`if CurProcIsStackless then Exit;` — a generator step function's locals are the
generator's live state, not locals going out of scope. **No cross arm has that
guard**, for any kind. The new arm carries `(not CurProcIsStackless)` inline as
a stopgap; the general hole is
`bug-a-a-managed-local-that-survives-a-yield-is-released-at-every-yield-on-every-cross-target`,
filed with a 12-line repro that SIGSEGVs on i386 and arm32 today.
