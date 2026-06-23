# bug: assigning a local dynamic-array-of-managed-record to a field drops/frees the elements

- **Type:** bug (Track A — codegen, managed dynamic-array assignment / refcount)
- **Status:** DONE 2026-06-23 (x86-64; cross targets documented below)
- **Found:** 2026-06-23, garin TDocModel.DeleteNode (Track B)
- **Severity:** medium — silent data loss; in a repeated-call path it escalates to
  a segfault. Easy to hit when rebuilding a managed array via a local temp.

## Resolution (2026-06-23)

The `field := localDynArray` path (whole dyn-array assignment into a non-IDENT
lvalue: a record/class field or nested sub-array slot) only copied the handle —
share-semantics with no refcount change — while the IDENT path (`localvar :=
dynArray`) was already ARC-correct via `IR_STORE_SYM`. So the local's scope-exit
release dropped the shared block to refcount 0 and freed it (and DecRef'd the
element strings), corrupting the field.

Added `IR_STORE_DYN` (defs.inc 60): an ARC-correct whole dyn-array store into a
slot ADDRESS — retain the new handle (skipped for a fresh function result that
already carries +1, matching `IR_STORE_SYM` move-semantics), publish it, then
element-aware release the old handle via `PXXDynArrayRelease` with a node-derived
descriptor (`GetOrAllocNodeDynDesc`). Lowering in `ir.inc` emits it for the
field/nested-slot dyn-array assign; codegen + `EmitDynArrayReleaseForNode` in
`ir_codegen.inc`; verifier + opcode-name updated.

Verified vs FPC: same-length rebuild (`Items := tmp`) now keeps the strings
across repeated reassigns, and the shrinking rebuild no longer segfaults.
Integer-array field assign unaffected. Self-host **byte-identical** (the compiler
itself uses managed dyn-array fields, now ARC-correct internally). `make test`
green. Regression: `test/test_dynarray_managed_field_reassign.pas`.

### Cross targets (deferred, no regression)

`IR_STORE_DYN` is emitted only when the target is x86-64; i386 / aarch64 /
arm32 / xtensa / riscv32 keep the existing bare-handle `IR_STORE_MEM` store
(same pre-existing share-semantics, so no regression, no new op to handle in
their codegen). Bringing the ARC store to the cross backends — each needs the
retain + element-aware-release asm — is a follow-up; cross managed-aggregate
support otherwise exists. The default target (where this was found and where
Track B builds) is fixed.

## Gap

Assigning a **local** dynamic array of a record that has a managed field
(`AnsiString`) to a **field** of the same type does not properly retain the
elements: after the assigning procedure returns, the record's managed-string
fields are freed/empty. A second such reassignment on the same object then reads
freed memory.

```pascal
type
  TRec = record Cap: AnsiString; P: Integer; end;
  TBag = class
    Items: array of TRec;
    Cnt: Integer;
    procedure Add(const c: AnsiString);
    procedure Shrink;   { rebuild Items from itself via a local, then reassign }
  end;
procedure TBag.Add(const c: AnsiString);
begin SetLength(Items, Cnt+1); Items[Cnt].Cap := c; Inc(Cnt); end;
procedure TBag.Shrink;
var tmp: array of TRec; i, n: Integer;
begin
  SetLength(tmp, Cnt); n := 0;
  for i := 0 to Cnt-1 do begin tmp[n] := Items[i]; Inc(n); end;
  Items := tmp;          { <-- whole-array assign from a local }
  Cnt := n;
end;
...
b.Add('a'); b.Add('b'); b.Add('c');
b.Shrink; writeln(b.Items[0].Cap);   { 'a'  — ok }
b.Shrink; writeln(b.Items[0].Cap);   { fpc: 'a'   pxx: ''  (string lost) }
```

Observed (pinned, 2026-06-23): first line prints `a`, second prints empty. With a
*shrinking* rebuild (fewer survivors) the same shape segfaults instead (the
original DeleteNode hit `Segmentation fault`).

## Likely cause

The `field := localDynArray` path for an array whose element is a managed record
doesn't bump the array/element refcount (or the per-element string refs), so the
local's cleanup at procedure exit frees data the field still points at.

## Control (works)

- A single assignment, with no read of the field inside the proc, is fine
  (`pdyn.pas`): the corruption shows on the *second* rebuild.
- **In-place compaction** (never reassign the array reference; mutate the
  existing `FNodes` and `SetLength` to shrink) works correctly — this is what
  `TDocModel.DeleteNode` now does. No app-logic distortion; arguably the better
  idiom anyway.

## Repro

`/tmp/pdyn2.pas` (above). `array of integer` is unaffected (no managed field);
the defect is specific to managed-element records.

## Track B impact

None outstanding — `DeleteNode` uses in-place compaction. Filed so the codegen
path gets fixed (any "rebuild a managed array via a temp and assign back" hits it).
