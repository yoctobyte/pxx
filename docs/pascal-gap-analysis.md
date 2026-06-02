# Pascal Language Feature Gap Analysis

FPC-reference-behavior detail for core Pascal mechanics, kept as a companion to
the live work list in [`todo.md`](todo.md) (which is authoritative for status).
This page keeps the per-feature reference descriptions; the live ✅/🟡/⬜ status
is in `todo.md` §4.

> **Backend note:** IR is the only active backend. The obsolete direct emitter
> was archived under `historic/` on 2026-05-31.

---

## 1. Core Features (mostly delivered)

The four daily-used mechanics that had to land for a robust Pascal dialect.
The active pointer gap is now closed; dynamic arrays retain their deliberate
allocator-dependent depth work.

### 1. Floating-Point Math (`Single` / `Double`) — ✅ implemented
* **Reference behavior**: Native IEEE-754 single and double precision support mapped to SSE2 registers (`XMM0`-`XMM7`).
* **Current state**: Implemented for scalar `Single`, `Double`/`Real`, and `Extended` storage; real literals including exponent notation; unary minus; mixed integer/float arithmetic; `/` as floating division; float comparisons; and Write/WriteLn (`x:w:n` exact and bare scientific). Coverage: `test/test_float.pas`.
* **Remaining gap**: explicit cast/rounding intrinsics `Trunc`, `Round`, `Float`, `Int` (tracked in `todo.md` §4).

### 2. Dynamic Arrays (`array of T`) — 🟡 partial
* **Reference behavior**: Heap-allocated arrays declared as `array of Type`. Resized at runtime via `SetLength(Arr, Size)`. Behind the scenes, dynamic arrays are pointers to heap blocks with size and reference count metadata stored immediately before the actual data:
  ```
  [-8 bytes]: Reference count (32-bit/64-bit integer)
  [-4 bytes]: Length / Element Count (32-bit integer)
  [Pointer]:  First element of the array
  ```
* **Current state**: Implemented for scalar element types and, under `{$define PXX_MANAGED_STRING}`, `array of AnsiString` plus arrays of records recursively containing `AnsiString` fields. `var a: array of T;` declares a pointer-sized slot holding a heap data pointer; `SetLength(a, n)` allocates a `[refcount(8)][length(8)][elements...]` block and stores the data pointer into the slot; `Length(a)` reads the length word with a nil-guard (unallocated → 0); indexed read/write are 0-based. Assignment retains/releases shared storage. Indexed writes clone shared array storage before mutation. Resize preserves the retained prefix, zeroes new slots, and reclaims replaced blocks; `SetLength(a, 0)` releases storage. Local slots initialize to nil and release on normal scope exit. Managed element arrays recursively retain copied strings and finalize them when their final array owner is released. Refcount updates become atomic only under `--threadsafe`. Coverage: `test/test_dynarray.pas`, `test/test_dynarray_ansistring.pas`, `test/test_dynarray_managed_record.pas`, `test/test_multithreading.pas`.
* **Remaining gaps**:
  - Whole-record assignment bookkeeping for managed records.
  - Nested dynamic arrays.
  - Dynamic arrays as parameters and function results.
  - Static-array fields embedded in records have an existing index-lowering
    bug and are not part of the managed-record array slice.
* **Ordering note**: recursive element lifecycle support needs richer element
  metadata than the current single `ElemType`. The cross-thread policy is
  fixed: atomic refcount updates are emitted only in threaded builds. Atomic
  counts protect lifetime only, not concurrent mutation or copy-on-write
  uniqueness checks.

### 3. General Pointer Syntax & Semantics (`^T`, `@`, `nil`) — ✅ implemented subset
* **Reference behavior**: Fully-typed pointer declarations (`^Integer`), explicit dereferencing caret operator (`Ptr^`), the address-of operator (`@Var`), and the predefined constant pointer value `nil` (0).
* **Current state**: Untyped `Pointer`, `nil`, `@Var`/`@arr[i]`, and `Ptr^` all work. Typed pointers cover named aliases `PFoo = ^TFoo`, indexing `p[i]`, record-pointer fields `p^.field`, casts `PType(expr)`, and scaled `p + n`, `p - n`, and `n + p`. Typed strides use the pointed-at element size; untyped pointers use byte stride. Tests: `test/test_ptr_alias.pas`, `test_ptr_deref_field.pas`, `test_ptr_cast.pas`, `test/test_ptr_arithmetic.pas`.

### 4. Sets & Set Operations (`set of T`) — ✅ implemented
* **Reference behavior**: Grouping discrete ordinal values together as bitsets (e.g., `set of Byte` or custom enums), literal declarations `[1, 2, 5..10]`, and the `in` operator.
* **Current state**: Set literals including ranges, `in` membership, set-typed published properties surfaced via RTTI (kind=SET), assignment, union, intersection, difference, equality, subset/superset comparisons, locals, record fields, parameters, and function results work. The IR uses dedicated 32-byte set operations and the shared aggregate-return ABI. Coverage: `test/test_sets.pas`, `test/test_set_shapes.pas`, `test/test_aggregate_results.pas`.

---

## 2. Parked / Excluded Features

### Interfaces (`interface` types)
* **Status**: **Intentionally deferred.** No current target source requires
  interfaces, while even a no-refcount model adds substantial dispatch, ABI,
  and lifetime-design surface. See [`todo.md`](todo.md) §3 for the retained
  scoping outline.

> Of the four core features above, floats, sets, and the covered typed-pointer
> surface are implemented; interfaces are intentionally deferred.
> [`todo.md`](todo.md) is the authoritative consolidated status list.
