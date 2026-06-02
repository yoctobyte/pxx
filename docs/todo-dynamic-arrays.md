# Dynamic Arrays: Remaining Work

**Snapshot:** 2026-06-02

Dynamic arrays are useful enough for container backends, but the language
feature is not complete. This document is the resume checklist for the next
dynamic-array session.

## Completed Surface

- Pointer-sized dynamic-array slots with layout
  `[refcount:8][length:8][elements...]`.
- Assignment retain/release.
- Indexed-write copy-on-write.
- `SetLength` grow, shrink, zero length, prefix preservation, and zeroed new
  slots.
- Normal local cleanup on procedure exit.
- Conditional atomic refcount updates under `--threadsafe`.
- Scalar element types.
- `array of AnsiString` under `{$define PXX_MANAGED_STRING}`.
- Arrays of fixed-size records recursively containing managed `AnsiString`
  fields.
- Class/object references remain unmanaged raw pointers. Their lifetime stays
  the user's responsibility.
- Dynamic arrays as procedure/function parameters (`array of T`). Open-array
  convention: the parameter slot borrows the caller's heap data pointer, so
  `Length` reads the heap header and element writes are visible to the caller.
- Dynamic arrays as function results (`function F: array of T`). The result is
  a pointer-sized heap handle built via `SetLength(Result, ...)`. Scalar and
  managed `AnsiString` element types both work.

Coverage:

```text
test/test_dynarray.pas
test/test_dynarray_ansistring.pas
test/test_dynarray_managed_record.pas
test/test_dynarray_params.pas
test/test_dynarray_result.pas
test/test_multithreading.pas
```

## High Priority Bug

Fix static-array field indexing inside records.

Example:

```pascal
type
  TEntry = record
    Tags: array[0..1] of AnsiString;
  end;

var
  a: array of TEntry;

begin
  SetLength(a, 1);
  a[0].Tags[0] := 'tag';
end.
```

During managed-record testing, `Tags[0]` lowered with an incorrect address and
wrote before the field. This is an existing address-lowering bug, not a
managed-reference-counting bug. Add a focused regression before fixing it.

Likely investigation area:

```text
compiler/ir.inc
compiler/parser.inc
```

## Remaining Dynamic-Array Work

1. Fix static-array field indexing inside records.
2. Add whole-record assignment bookkeeping for records containing managed
   fields. Raw `rep movsb` is incorrect because copied references must be
   retained and replaced destination fields must be released. The compiler
   currently rejects this case explicitly:

   ```text
   whole-record assignment with managed fields not yet supported
   ```

3. ~~Add dynamic arrays as procedure parameters.~~ Done.
4. ~~Add dynamic arrays as function results.~~ Done.
5. Add nested dynamic arrays such as `array of array of Integer`.
6. Extend recursive lifecycle metadata for nested dynamic arrays and records
   containing them.
7. Add exception-path cleanup only if exception lifetime semantics become an
   active requirement. Normal scope-exit cleanup is implemented.

### Known limitation: result refcount off-by-one

A dynamic-array function result is built in the `Result` slot with refcount 1
and is excluded from scope-exit release (it is the return value). The caller's
assignment (`a := F(...)`) then unconditionally retains it, so the handle keeps
refcount 2 with a single owner — a one-reference leak, never a double free.
This matches the existing managed-`AnsiString` result behaviour. A real fix
needs move semantics at the assignment site (skip the retain when the RHS is a
fresh call result).

## Implementation Notes

Managed records are fixed-size records containing compiler-managed value
slots. They are not variable-size records. Heap-backed payloads live behind
pointer-sized fields.

Recursive lifecycle helpers currently live in:

```text
compiler/symtab.inc: RecordHasManagedFields
compiler/ir_codegen.inc: EmitManagedRecordRetain
compiler/ir_codegen.inc: EmitManagedRecordReleaseLocked
compiler/ir_codegen.inc: EmitDynArrayManagedRecReleaseLocked
```

Do not add automatic ownership for class/object references. Copy them as raw
pointers only.

## Verification Gate

Run:

```sh
make test
make test-nilpy
git diff --check
```
