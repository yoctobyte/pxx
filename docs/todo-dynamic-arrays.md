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

## High Priority Bug — FIXED 2026-06-02

Static-array indexing of managed `AnsiString` now works (standalone, record
field, and dyn-array-of-record field). Regression:
`test/test_static_array_ansistring_field.pas`.

Three independent defects were responsible:

1. `RecFieldIsArray` ignored user record/class fields (only handled the
   hardcoded `REC_TPROC.Params`), so `IsNodeArray(field)` returned false and the
   parser typed `e.Tags[0]` as a `Char` (scalar string char-index) instead of an
   `AnsiString` element. Fixed by consulting `UFldIsArray` for `REC_UCLASS_BASE+`.
2. `IR_LEA` treated a *static array of AnsiString* like a scalar managed string
   (load-value `mov` instead of address `lea`) on the read path, so indexing
   operated on the string pointer rather than the array base. Guarded the
   managed-scalar branch with `not IsArray`.
3. `IR_INDEX` ran copy-on-write (`AnsiStrUnique`) when the base was an
   `IR_FIELD` of type `tyAnsiString`, without checking the field was a scalar
   string — for an array-of-AnsiString field this clobbered the destination
   address to 0 and segfaulted on write. Guarded with `elemSize = 1`
   (char-index stride) vs 8 (array element stride).

### Related, still broken (separate, pre-existing)

Char-indexed *read* of a scalar `AnsiString` record field (`c := r.s[1]`)
returns a blank/garbage char. Char-indexing a plain `AnsiString` *variable*
works. Out of scope for the static-array fix; investigate the `IR_FIELD`
char-read path separately.

## Remaining Dynamic-Array Work

1. ~~Fix static-array field indexing inside records.~~ Done (see above).
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
