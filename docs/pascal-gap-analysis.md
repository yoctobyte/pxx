# Pascal Language Feature Gap Analysis

An active analysis of the remaining core Pascal language features to be implemented in **Frankonpiler**, relative to Free Pascal Compiler (FPC) as the reference compiler.

---

## 1. High-Priority Features

These four features represent the most critical, daily-used language mechanics in Pascal. Their implementation will make the compiler's Pascal dialect fully robust for standard applications.

### 1. Floating-Point Math (`Single` / `Double`)
* **Reference behavior**: Native IEEE-754 single and double precision support mapped to SSE2 registers (`XMM0`-`XMM7`).
* **Current state**: Implemented in the direct x86-64 backend for scalar `Single`, `Double`/`Real`, and `Extended` storage; real literals including exponent notation; unary minus; mixed integer/float arithmetic; `/` as floating division; and float comparisons. Coverage is tracked by `test/test_float.pas`.
* **Remaining gaps**:
  - Write/WriteLn of float values.
  - Explicit cast/rounding intrinsics such as `Trunc`, `Round`, `Float`, and `Int`.
  - Complete IR-backend parity for float literals and operations.

### 2. Dynamic Arrays (`array of T`)
* **Reference behavior**: Heap-allocated arrays declared as `array of Type`. Resized at runtime via `SetLength(Arr, Size)`. Behind the scenes, dynamic arrays are pointers to heap blocks with size and reference count metadata stored immediately before the actual data:
  ```
  [-8 bytes]: Reference count (32-bit/64-bit integer)
  [-4 bytes]: Length / Element Count (32-bit integer)
  [Pointer]:  First element of the array
  ```
* **Current state**: Completely absent. The compiler currently only supports static arrays (`array[Low..High] of Type`).
* **Benefits**: Distinct declaration format means this will not touch or conflict with static array structures.

### 3. General Pointer Syntax & Semantics (`^T`, `@`, `nil`)
* **Reference behavior**: Fully-typed pointer declarations (`^Integer`), explicit dereferencing caret operator (`Ptr^`), the address-of operator (`@Var`), and the predefined constant pointer value `nil` (0).
* **Current state**: Pointer storage size and untyped `Pointer` type are fully functional. However, standard pointer syntax (caret operations) is restricted.

### 4. Sets & Set Operations (`set of T`)
* **Reference behavior**: Grouping discrete ordinal values together as bitsets (e.g., `set of Byte` or custom enums), literal declarations `[1, 2, 5..10]`, and the `in` operator.
* **Current state**: The parser has basic stubs for `in`, but sets are not a fully implemented standard type with storage and algebraic operations.

---

## 2. Parked / Excluded Features

### ❌ Interfaces (`interface` types)
* **Status**: **Parked indefinitely.**
* **Rationale**: Interfaces in Delphi/FPC are heavily tied to Windows and COM objects (incorporating GUIDs, reference counting via `_AddRef`/`_Release`, and multiple VMT layouts). Since Frankonpiler targets purely lightweight Linux ELF execution, **Windows/COM interfaces are entirely excluded from the project roadmap.**
