# Pascal Language Feature Gap Analysis

An active analysis of the remaining core Pascal language features to be implemented in **Frankonpiler**, relative to Free Pascal Compiler (FPC) as the reference compiler.

---

## 1. High-Priority Features

These four features represent the most critical, daily-used language mechanics in Pascal. Their implementation will make the compiler's Pascal dialect fully robust for standard applications.

### 1. Floating-Point Math (`Single` / `Double`)
* **Reference behavior**: Native IEEE-754 single and double precision support mapped to SSE2 registers (`XMM0`-`XMM7`).
* **Current state**: Implemented in the direct x86-64 backend for scalar `Single`, `Double`/`Real`, and `Extended` storage; real literals including exponent notation; unary minus; mixed integer/float arithmetic; `/` as floating division; and float comparisons. Coverage is tracked by `test/test_float.pas`.
* **Remaining gaps**:
  - Write/WriteLn of float values: **done** — fixed `x:w:n` (exact) and bare scientific, both backends.
  - Explicit cast/rounding intrinsics such as `Trunc`, `Round`, `Float`, and `Int`.
  - IR-backend parity: **done** — floats work under `--experimental-ir-codegen`.

### 2. Dynamic Arrays (`array of T`)
* **Reference behavior**: Heap-allocated arrays declared as `array of Type`. Resized at runtime via `SetLength(Arr, Size)`. Behind the scenes, dynamic arrays are pointers to heap blocks with size and reference count metadata stored immediately before the actual data:
  ```
  [-8 bytes]: Reference count (32-bit/64-bit integer)
  [-4 bytes]: Length / Element Count (32-bit integer)
  [Pointer]:  First element of the array
  ```
* **Current state**: Implemented in the direct x86-64 backend for scalar element types. `var a: array of T;` declares a pointer-sized slot holding a heap data pointer; `SetLength(a, n)` bump-allocates a `[refcount(8)][length(8)][elements...]` block and stores the data pointer into the slot; `Length(a)` reads the length word with a nil-guard (unallocated → 0); indexed read/write are 0-based. Distinct declaration format from static arrays, so no conflict with `array[Low..High]`. Coverage tracked by `test/test_dynarray.pas`.
* **Remaining gaps**:
  - `SetLength` always fresh-allocates; old contents are not preserved on regrow, and freed blocks are not reclaimed (no reference counting / copy semantics yet).
  - Dynamic `array of record` / `array of string` element types.
  - Dynamic arrays as parameters and function results.
  - IR-backend parity: **done** — dynamic arrays work under `--experimental-ir-codegen`.

### 3. General Pointer Syntax & Semantics (`^T`, `@`, `nil`)
* **Reference behavior**: Fully-typed pointer declarations (`^Integer`), explicit dereferencing caret operator (`Ptr^`), the address-of operator (`@Var`), and the predefined constant pointer value `nil` (0).
* **Current state**: Pointer storage size and untyped `Pointer` type are fully functional. However, standard pointer syntax (caret operations) is restricted.

### 4. Sets & Set Operations (`set of T`)
* **Reference behavior**: Grouping discrete ordinal values together as bitsets (e.g., `set of Byte` or custom enums), literal declarations `[1, 2, 5..10]`, and the `in` operator.
* **Current state**: The parser has basic stubs for `in`, but sets are not a fully implemented standard type with storage and algebraic operations.

---

## 2. Parked / Excluded Features

### Interfaces (`interface` types)
* **Status**: **Planned** (superseded — was previously parked). The next big
  language feature, scheduled after the Lazarus/LCL streaming arc. See
  [`todo.md`](todo.md) §3 for the scoping outline.
* **Note**: The earlier "park indefinitely" rationale (COM/Windows baggage) is
  retired. We do not need COM. The plan is a lightweight Linux-native model
  (CORBA-style / no-refcount first; COM-style ARC deferred). GUIDs optional.

> This document is partially superseded — sets and floating point listed above
> as gaps are now implemented, and interfaces are now planned. See
> [`todo.md`](todo.md) for the current consolidated list.
