---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`b := a` on a record holding a COM interface field copies the pointer with no retain, so the two records share one counted reference. Nilling either one destroys the object and the other is left dangling — a use-after-free that segfaults on the next member call. Present on pinned and on HEAD."
status: done
owner: agent-A
---

# A record copy does not retain an interface field

- **Track A** (`compiler/ir.inc` record-copy path; the record descriptor in
  `compiler/rtti_emit.inc` / `builtinheap`'s `PXXRecordRelease`).
- Found 2026-08-20 alongside
  `bug-a-a-record-with-an-interface-field-is-not-zero-initialised`, which fixed
  the init half of the same design problem.

## Measured

Globals, so zero-init is not involved — this is purely the copy:

```pascal
type TRec = record a: Integer; f: IFoo; end;
var a, b: TRec;
begin
  a.f := TFoo.Create('x');
  b := a;
  a.f := nil;
  writeln('destroyed = ', destroyed);   { FPC: 0    pxx: 1 }
  writeln(b.f.Name);                    { FPC: x    pxx: SIGSEGV }
end;
```

Identical on the pinned binary and on HEAD.

## Cause

The copy path picks `IR_COPY_REC_MANAGED` (release dest's old managed fields,
retain src's) over the raw `IR_COPY_REC` using `RecordHasManagedFields` — the
FINALIZATION predicate, which deliberately excludes COM interface fields because
releasing one under the non-reentrant record heap lock deadlocks
(`bug-a-class-managed-fields-not-finalized-on-destroy`).

So a record whose only refcounted member is an interface takes the raw copy and
the reference is never counted.

## Why it was not fixed with the init half

Flipping the predicate would enable BOTH the managed copy and scope-exit
finalization, and the finalization half is exactly what deadlocks. The retain
side is harmless on its own (`_AddRef` frees nothing), but the managed copy also
RELEASES the destination's old fields, which can free — so this needs the record
descriptor to describe interface members and a release path that runs outside the
heap lock. That is the same blocked design work as the finalization ticket, and
it should be done once for both.

## Suggested approach

Do it with `bug-a-class-managed-fields-not-finalized-on-destroy`, not before:

1. Give the record descriptor an interface member kind carrying the iface id.
2. Make the interface release pass run OUTSIDE the heap spinlock (a separate
   unlocked pass, or make the lock reentrant) — the blocker both tickets share.
3. Then `RecordHasManagedFields` can count interface fields, and copy,
   scope-exit finalization and destructor finalization all follow from the one
   predicate. `RecordNeedsZeroInit` collapses back into it at that point.

## Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`. Add the
copy case to `test/test_record_interface_field_zero_init.pas`, which currently
asserts only that the init crash is gone.

## 2026-08-21 — claimed, then released unworked (Track A)

Picked up with the array family
([[bug-a-a-local-array-of-interfaces-is-never-released-at-scope-exit]] and its
siblings) and put back: it does NOT share their escape route.

The array family turned out to be fixable without the lock decision because its
walks are unlocked (static arrays) or gatable at one point (dyn arrays, where
`ManagedElemKindLocked` refuses kind 4 under `--threadsafe` and keeps the
pre-existing leak instead of a hang). This ticket has neither property: a record
copy's RELEASE of the destination's old interface field is the thing that frees,
it runs from the record-field path that holds the heap lock, and the record
descriptor's managed-field predicate is shared with FINALIZATION — so widening
it turns on both halves at once, and the finalization half is what deadlocks.

Still `blocked-by: decide-interface-members-in-aggregates-lock-strategy`. That
decision is now the ONLY thing standing between this family and completeness,
which raises its value: everything around it has landed.

## 2026-08-21 — UNBLOCKED: the decision landed, and it is (b)

[[decide-interface-members-in-aggregates-lock-strategy]] was answered by the
user: **a separate unlocked interface pass**, the shape already shipping for
class fields (`PXXClassFinalize` runs its kind-4 pass first, unlocked).

That dissolves the objection recorded above rather than gating around it. The
note said this ticket had no escape route because *"the record descriptor's
managed-field predicate is shared with FINALIZATION — so widening it turns on
both halves at once, and the finalization half is what deadlocks."* Under (b)
the interface retain **and** release both move ahead of `EmitAcquireHeapLock`,
so widening the predicate no longer enables a *locked* release. There is no
deadlock left to gate, hence no `ThreadSafeMode` refusal of the kind
`ManagedElemKindLocked` needed for dynamic arrays.

Consequence: the use-after-free is fixed in **every** build. Do not implement
option (c) (retain-only, trading the UAF for a leak) — it was a fallback for the
case where this decision stayed open, and it has not.

## Resolution 2026-08-21 (Track A)

Fixed in **every** build, native and cross, exactly as the unblocking note
predicted: the interface half of the walk moved AHEAD of the lock, so widening
the predicate no longer enables a locked release and there is nothing left to
gate on `ThreadSafeMode`.

**One predicate again.** `RecordHasManagedFields` counts COM interface fields
(`inclIntf` is True from both callers), so `RecordNeedsZeroInit` is the same walk
under a name that says which question it answers. That single flip is what routes
an interface-only record through `IR_COPY_REC_MANAGED` instead of the raw byte
copy — the actual bug.

**Two walks, split by lock discipline, not by member kind.** The record layout
descriptor now carries kind-4 members (`RecordDescMember` = `FieldIsManaged` or
`FieldIsComInterface`; typeRef holds the interface id, the same discriminated
slot the CLASS descriptor and the kind-4 array descriptors already use). New
runtime helpers `PXXRecordRetainIntf` / `PXXRecordReleaseIntf` walk ONLY kind 4
(recursing through kind-3 sub-records) and are emitted BEFORE
`EmitAcquireHeapLock`; `PXXRecordRetain` / `PXXRecordRelease` keep kinds 1-3 and
stay inside it. Same shape `PXXClassFinalize` has shipped with.
`PXXRecordReleaseIntf` deliberately does NOT nil the slot: the copy path releases
the DESTINATION before the bulk copy, and for `a := a` that is the same memory.

**Sites**: the copy arm on all five backends that have one (x86-64 / i386 /
arm32 / aarch64 / riscv32 — xtensa has no managed record copy), the record
scope-exit arm on all five, and the aggregate-return destination release on all
five. Scope exit is NOT optional here: retaining on copy without releasing at
scope exit would trade the use-after-free for a leak per copy, which is worse
than what it replaced.

**Measured against FPC 3.2.2**, same program each time:

| shape | FPC | pxx before | pxx after |
| --- | --- | --- | --- |
| `b := a`, then nil `a`, read `b.f.Name` | `x` | **SIGSEGV** | `x` |
| destroyed after nilling both | 1 | 0 (dangling) | **1** |
| `x := x` (self-assign) | alive, then 1 | alive, then 1 | **alive, then 1** |
| nested `TNest.inner.f` copy | 1 | SIGSEGV | **1** |
| copy over a live target | old dies immediately | never | **immediately** |
| local copy released at scope exit | 1 | 0 | **1** |
| mixed record (string + iface + dynarray + int) | all five values | — | **identical** |

Cross-checked under qemu on **aarch64 / arm32 / i386 / riscv32**: the extended
`test/test_record_interface_field_zero_init.pas` prints `total ok 10 / 10` on
every one, and under `--threadsafe` it TERMINATES (10/10) — the property that
would fail if the interface release had stayed under the spinlock.

## Residuals, deliberately not folded in

- **A by-value record argument's temp is released at the CALLER's scope exit,
  not at the call's end.** FPC finalizes a value parameter in the callee, so a
  destroy that FPC shows immediately after the call shows later here — visible
  only when the caller is the main program body, where "later" is program exit.
  A temp-lifetime divergence that predates this ticket and is not interface-
  specific: filed as [[bug-a-by-value-record-arg-temp-outlives-the-call]].
- **An ARRAY (static or dynamic) of records-with-interface-fields** still leaks
  the interfaces: the element walk calls `PXXRecordRelease` (kinds 1-3) with no
  interface pass. Same fix shape, one level out; filed as
  [[bug-a-array-of-records-with-interface-fields-leaks-the-interfaces]].

Gate: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-21 — resolved, commit 6510a77d5.
