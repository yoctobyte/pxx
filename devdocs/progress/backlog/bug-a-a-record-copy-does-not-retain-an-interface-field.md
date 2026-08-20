---
track: A
prio: 60
type: bug
blocked-by: [decide-interface-members-in-aggregates-lock-strategy]
summary: "`b := a` on a record holding a COM interface field copies the pointer with no retain, so the two records share one counted reference. Nilling either one destroys the object and the other is left dangling — a use-after-free that segfaults on the next member call. Present on pinned and on HEAD."
status: working
owner: claude-acp
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
