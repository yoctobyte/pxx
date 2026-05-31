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
Three of the four are now implemented; pointers retain one gap (arithmetic).

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
* **Current state**: Implemented for scalar element types. `var a: array of T;` declares a pointer-sized slot holding a heap data pointer; `SetLength(a, n)` allocates a `[refcount(8)][length(8)][elements...]` block and stores the data pointer into the slot; `Length(a)` reads the length word with a nil-guard (unallocated → 0); indexed read/write are 0-based. Distinct declaration format from static arrays, so no conflict with `array[Low..High]`. Coverage: `test/test_dynarray.pas`.
* **Remaining gaps**:
  - `SetLength` always fresh-allocates; old contents are not preserved on regrow, and freed blocks are not reclaimed (no reference counting / copy semantics yet).
  - Dynamic `array of record` / `array of string` element types.
  - Dynamic arrays as parameters and function results.

### 3. General Pointer Syntax & Semantics (`^T`, `@`, `nil`) — 🟡 partial
* **Reference behavior**: Fully-typed pointer declarations (`^Integer`), explicit dereferencing caret operator (`Ptr^`), the address-of operator (`@Var`), and the predefined constant pointer value `nil` (0).
* **Current state**: Untyped `Pointer`, `nil`, `@Var`/`@arr[i]`, and `Ptr^` all work. Typed pointers C1–C4 are done: named aliases `PFoo = ^TFoo`, indexing `p[i]` (element-size stride), record-pointer fields `p^.field`, and casts `PType(expr)`. Tests: `test/test_ptr_alias.pas`, `test_ptr_deref_field.pas`, `test_ptr_cast.pas`.
* **Remaining gap**: scaled pointer arithmetic `p + n` (currently unscaled/garbage; indexing `p[i]` is the working substitute). See `todo.md` §4.

### 4. Sets & Set Operations (`set of T`) — ✅ implemented
* **Reference behavior**: Grouping discrete ordinal values together as bitsets (e.g., `set of Byte` or custom enums), literal declarations `[1, 2, 5..10]`, and the `in` operator.
* **Current state**: Set literals including ranges, `in` membership, set-typed published properties surfaced via RTTI (kind=SET), assignment, union, intersection, difference, equality, subset/superset comparisons, locals, record fields, and parameters work. The IR uses dedicated 32-byte set operations. Coverage: `test/test_sets.pas`, `test/test_set_shapes.pas`.
* **Remaining gap**: set-valued function results need the general aggregate-return ABI.

---

## 2. Parked / Excluded Features

### Interfaces (`interface` types)
* **Status**: **Planned** (superseded — was previously parked). The next big
  language feature, scheduled after the Lazarus/LCL streaming arc. See
  [`todo.md`](todo.md) §3 for the scoping outline.
* **Note**: The earlier "park indefinitely" rationale (COM/Windows baggage) is
  retired. We do not need COM. The plan is a lightweight Linux-native model
  (CORBA-style / no-refcount first; COM-style ARC deferred). GUIDs optional.

> Of the four core features above, floats and sets are implemented,
> and typed pointers are done bar arithmetic; interfaces are planned (not parked).
> [`todo.md`](todo.md) is the authoritative consolidated status list.
