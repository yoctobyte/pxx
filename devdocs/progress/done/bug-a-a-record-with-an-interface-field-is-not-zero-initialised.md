---
track: A
prio: 70
type: bug
blocked-by: []
summary: "A local record holding a COM interface field was never zero-initialised, so the first assignment to that field released STACK GARBAGE and dispatched _Release through a junk IMT. The exclusion of interface fields from RecordHasManagedFields was a deliberate, documented trade — but that one predicate was answering both the FINALIZATION question (where the trade is right) and the ZERO-INIT question (where it cannot deadlock and must not be skipped), which turned an intended benign leak into a use-after-free."
status: done
owner: claude-acp
---

# A record with an interface field is not zero-initialised

- **Track A** (`compiler/symtab.inc` predicates, `compiler/parser.inc`
  `EmitManagedLocalsZeroInit`).
- Found 2026-08-20 by an FPC differential probe of interfaces held in
  aggregates — the case the sibling array ticket explicitly flagged as untested.

## Measured

```pascal
type TRec = record a: Integer; f: IFoo; end;
procedure P;
var r: TRec;
begin
  r.f := TFoo.Create('r');   { SIGSEGV }
end;
```

| variant | pinned pxx | FPC |
| --- | --- | --- |
| local record, **dirty** stack | **SIGSEGV** | clean |
| local record, clean stack | clean | clean |
| global record | clean | clean |
| class instance field | clean | clean |

Only the local case fails, and only when the frame holds non-zero garbage —
which is why it hid: a clean stack makes the bug invisible.

## Cause, and the decision that produced it

`RecordHasManagedFields` deliberately does NOT count a COM interface field, and
the code says why:

> finalizing it under the record heap lock deadlocks: the record-scope
> finalization holds the non-reentrant heap spinlock and the interface's
> `_Release -> Free -> FreeMem` re-acquires it … Until then a COM interface
> record field leaks (benign) rather than deadlocking.

That reasoning is sound **for finalization**. The defect is that the same
predicate also gated `EmitManagedLocalsZeroInit`. Zero-init takes no lock, calls
no `_Release`, and cannot deadlock — it writes zeros into a stack slot at routine
entry. Skipping it does not produce the leak the comment promises; it produces a
**use-after-free**, because the first `r.f := x` correctly releases the old
occupant and the old occupant is stack junk.

**One predicate, two questions, opposite right answers.** The comment documented
the trade honestly and the trade was never actually made.

## Fix

Thread an `inclIntf` flag through the record walk and split the wrappers:

- `RecordHasManagedFields` — FINALIZATION. Unchanged: interface fields excluded,
  deadlock avoided, the documented leak preserved.
- `RecordNeedsZeroInit` — INIT. Same walk, plus COM interface fields.

`EmitManagedLocalsZeroInit` now asks the second one, for both the scalar-record
and the array-of-records arm.

## Still true by design

The field is still never RELEASED, so it leaks — exactly the intended trade, and
it belongs to `bug-a-class-managed-fields-not-finalized-on-destroy`. The test
asserts the crash is gone, NOT that the object is destroyed: `destroyed` stays 0
where FPC reports 1, and that is deliberate.

## Third instance of one gap

Scalar interface locals were handled; `array[0..N] of IFoo` was not
(`bug-a-a-local-array-of-interfaces-is-not-zero-initialised`); a record with an
interface field was not. `root-cause-over-microfix.md` calls three a design flaw,
and the flaw is that "is this thing refcounted?" is asked through predicates
keyed on the CONTAINER's shape (`SymIsComInterface` says False for an array,
`RecordHasManagedFields` says False for an interface field) rather than on the
member. The two helpers added across these fixes — `RecIsComInterface` and
`SymElemIsComInterface` — are the beginning of the member-keyed form; a follow-up
that routes every managed-slot pass through one walk would delete the remaining
arms.

## Found in passing — a separate use-after-free, NOT fixed here

Record ASSIGNMENT does not retain an interface field either, because the copy
path is chosen by the same finalization predicate:

```pascal
a.f := TFoo.Create('x');
b := a;            { raw copy: b.f aliases a.f with no count }
a.f := nil;        { refcount hits 0, object destroyed }
writeln(b.f.Name); { SIGSEGV — pinned and HEAD alike }
```

Filed as `bug-a-a-record-copy-does-not-retain-an-interface-field`. Not folded in
because the clean fix needs the record DESCRIPTOR to carry interface members,
which is the same blocked design problem as the finalization deadlock.

## Test

`test/test_record_interface_field_zero_init.pas` — 5/5, identical to FPC. Plain
field, nil store, an interface nested one record deep, overwrite, and a local
array of such records; each preceded by an explicit stack-dirtying call so the
failure is deterministic. **The pinned binary segfaults on row 2.**

## Gate

`make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`.
