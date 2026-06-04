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
test/test_nested_dynarray.pas
test/test_nested_dynarray_managed.pas
test/test_ansistring_record_char_read.pas
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

### Related char-read bug — FIXED 2026-06-02

Char-indexed *read* of a scalar `AnsiString` record field (`c := r.s[1]`)
now loads the managed-string data pointer from the `IR_FIELD` slot before
applying the character index. Writes still pass the slot address to
`AnsiStrUnique` for copy-on-write. Regression:
`test/test_ansistring_record_char_read.pas`.

## Remaining Dynamic-Array Work

1. ~~Fix static-array field indexing inside records.~~ Done (see above).
2. ~~Add whole-record assignment bookkeeping for records containing managed
   fields.~~ Done 2026-06-02. `IR_COPY_REC_MANAGED` retains the source's managed
   fields, releases the destination's old ones (under the heap lock), then bulk
   copies. Retain-before-release makes self-assignment and shared fields safe.
   Record/managed-array locals are now zero-initialised so the release of the
   (nil) old destination fields is safe. Regression:
   `test/test_managed_record_assign.pas`. Returning a managed record *by value*
   via the function-name result form (`FuncName := rec`) is now ARC-correct
   too: the LHS ASTTk is unset (0) on that form, so `AN_ASSIGN` formerly fell
   through to the scalar store path and copied only the first qword — `s`
   survived, the scalar tail (`n`) was truncated to its zero-init value. Fixed
   2026-06-03 by also keying the record-copy branch on the LHS symbol's
   `TypeKind` (`ir.inc` `AN_ASSIGN`), so it lowers to `IR_COPY_REC_MANAGED`
   (full `RecSize`, retain-before-release). Regression:
   `test/test_managed_record_funcname_return.pas`.

3. ~~Add dynamic arrays as procedure parameters.~~ Done.
4. ~~Add dynamic arrays as function results.~~ Done.
5. ~~Add nested dynamic arrays such as `array of array of Integer`.~~ Done
   2026-06-02. Scalar and managed base element types, any depth. Each level is
   an independent `[refcount][length][data]` heap block of pointer-sized
   sub-array handles;
   the deepest level holds base elements. `SetLength` works on the outer array
   and on any sub-array element (`IR_SETLEN_DYN` on a target slot address);
   `Length` reads each level's header; sub-arrays are released recursively on
   scope exit / reassignment (`EmitDynArrayNestedReleaseLocked`). Depth is
   tracked in the `SymDynDepth` parallel array (NOT a `TSymbol` field — adding a
   field to that record breaks self-host: it pushes the compiler's own record
   field count past the limit, see below). Regression:
   `test/test_nested_dynarray.pas`.
   - **Copy-on-write at nested levels — DONE 2026-06-04.** A write through a
     nested index (`b[i][j] := v`) now clones every shared level along the path
     so an aliased array (`b := a`) is never mutated in place. The nested-index
     lowering wraps each level's handle slot in `IR_DYNUNIQUE` (`ir.inc`), which
     at codegen loads the data pointer on a read and clones-if-shared on a write
     (keyed on the same `InLValueWrite` the depth-1 outer array uses), recursing
     up the chain. Cloning a level retains what its elements own — sub-array
     handles for inner levels, managed strings/records at the leaf — via the
     metadata-driven `EmitDynArrayUniqueMeta`; the old block is freed through
     `EmitDynArrayNestedReleaseLocked`. The root's slot address uses the new
     `IR_SLOTADDR` op (a quirk-free `lea`) because `IR_LEA` auto-loads a
     dyn-array handle on reads. The compiler itself uses no nested dynamic
     arrays, so the self-host build stays byte-identical. Regression:
     `test/test_nested_cow.pas` (2-/3-level, nested managed strings, sibling
     integrity, 2M-iteration alias+write loop flat at 264 KB).
6. ~~Extend recursive lifecycle metadata for nested dynamic arrays of
   *managed* base types.~~ Done 2026-06-02. Nested `AnsiString` and recursively
   managed-record leaves retain copied values during resize and finalize them
   recursively on shrink, reassignment, and scope exit. Coverage:
   `test/test_nested_dynarray_managed.pas`.
7. Add exception-path cleanup only if exception lifetime semantics become an
   active requirement. Normal scope-exit cleanup is implemented.

### Result refcount off-by-one — FIXED 2026-06-04

A managed function result (dynamic array or `AnsiString`) is built in the
`Result` slot at refcount 1 and excluded from scope-exit release. The caller's
assignment (`a := F(...)`) used to unconditionally retain it, so the handle kept
refcount 2 with a single owner — a one-reference leak per assignment.

Fixed by move semantics at the store: `IR_STORE_SYM` / `IR_STORE_MEM` now skip
the retain when the RHS is a fresh user-function result (`IRKind = IR_CALL` and
`IRA >= 0`), mirroring the pre-existing skip for concat (`IR_BINOP`) results.
Intrinsic results (`IRA < 0`) keep the conservative retain. The move is safe
because every return path is `Result := X`, which already establishes the +1
destined for the caller. Regression: `test/test_managed_result_move.pas`
(alias-survives-reassignment, the over-free risk). A/B on a 5M-iteration
`s := Mk('a','b')` loop: peak RSS 507 MB → 351 MB.

The residual 351 MB is a **separate** leak (`tools` v2 probe): managed string
*arguments* are not released on callee return. `s := Mk('hello')` leaks the
per-call arg string (~31 B/iter); a no-arg `Mk` result loop is flat (264 KB).
Tracked below.

### Managed string argument temporaries leaked — FIXED 2026-06-04

A materialised managed `AnsiString` argument (a literal, concat, char/string
coercion, or function result — anything that is not an existing lvalue) is
refcount 1 with no owner, so passing it directly leaked one reference per call.
Params stay *borrowed* (the "borrow by default" law): existing-variable args
were already clean.

Fixed by binding each such temporary to a hidden owning local at the call site
(`ir.inc`, `AN_CALL` arg loop): the temp is stored into a synthesised
`tyAnsiString` local (the store releases the previous value, covering loop
reuse) and passed by borrow; the epilog's managed-local release frees it at
scope exit. The hidden locals are created during body lowering — after the
parser's prologue zero-init pass — so `IREmitMachineCode` nil-inits them
(flagged via the `SymIsHiddenArgTemp` parallel array) before the body, keeping
the first store's release-of-old safe. Only fires under `PXX_MANAGED_STRING`
(`tyAnsiString` exists only then), so the self-hosted compiler build is
byte-identical. Regression: `test/test_managed_arg_temp.pas`.

A/B over a 5M-iteration `s := Mk('a','b')` loop: peak RSS 507 MB (pre-result-fix)
→ 351 MB (result move) → **264 KB** (arg temps owned). A no-arg result loop and
a variable-arg loop were already flat at 264 KB.

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
compiler/ir_codegen.inc: EmitDynArrayNestedReleaseLocked
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
