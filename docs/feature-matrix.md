# PXX Language Feature Matrix

This matrix tracks proposed dialect additions, standard extensions, and compiler enhancements discussed for the Pascal and Python frontends of PXX, evaluating their complexity, compliance, and priority.

| Feature | Standardization | Implementation Complexity | Priority / Use Case | Status | Description |
|---|---|---|---|---|---|
| **PChar $\rightarrow$ String Coercion** | **Standard** (FPC/Delphi compatible) | **Low-Medium** | **Critical** / Unblocks clean C-header use | ✅ Delivered | Auto-generate copying loops when assigning or casting `PChar` to a Pascal `string`/`AnsiString`. |
| **Auto-Typed Variables (`var a: auto`)** | **Dialect** (Modern Object Pascal has inline `var`) | **Low** | **High** / Ergonomics for wrapperless C imports | ⬜ Planned | Deferred type-inference. The variable is declared as `auto` and statically locks into the type of its first RHS assignment. |
| **Nested Subroutines** | **Standard** (Wirth Pascal core) | **High** | **Medium** / Structural modularity | ⬜ Deferred | Functions declared inside functions. Requires lexical scoping (passing a stack frame static-link pointer to inner scopes). |
| **Out-Param Return-Lifting** | **Dialect** | **None** (Shared with Python) | **Done** | ✅ Delivered | Trailing `T**` C out-parameters are lifted to the call's return value (e.g., `db := sqlite3_open(path)`). |
| **Dynamic `any` Type** | **Dialect** (Variant concept) | **Very High** | **Low** / Scripting helper | ⬜ Excluded | Dynamic types with runtime tagging and dispatch. Discarded to keep compiler bootstrap lightweight. |

---

### Technical Q&A: `PChar(s)` vs `@s[1]`

* **The Question:** Is `PChar(s)` the same as `@s[1]`, and is there a difference regarding `nil` safety?
* **The Answer:** Yes, there is a critical difference in **nil-safety**:
  1. **Empty String Representation:** In PXX (as in Free Pascal), empty managed `AnsiString` variables are represented by a `nil` pointer (0) to save allocation overhead.
  2. **`@s[1]` (Dangerous):** Accessing `s[1]` on an empty string tries to reference the first character. Because the string is `nil`, this attempts a dereference of address `0` (or `0 + 8` for length offset), causing an immediate **Segmentation Fault**.
  3. **`PChar(s)` (Safe):** If `s` is `nil` (empty), `PChar(s)` evaluates safely to `nil` (0). Since C library calls (like SQLite) frequently accept `nil` to denote optional or empty string arguments, `PChar(s)` behaves correctly and safely.

---

### Architectural Advice on `PChar` (Cast vs. Normal Function)

While it is tempting to implement `PChar` as a regular library function, it **must remain a compiler-recognized typecast/builtin** for lifetime and memory correctness:
* **The Dangling Pointer Risk:** If `PChar(s)` were a normal function, passing the string `s` by-value would make a temporary local copy of the string in the function's stack frame. Returning a pointer to this copy would immediately create a **dangling pointer** once the function returns.
* **Inline Strings:** For legacy inline/frozen strings, the compiler must offset the variable's frame address by `+8` to skip the length prefix. A normal function cannot inspect the caller's frame layouts dynamically. 
* **Conclusion:** Keeping `PChar` as an AST-level cast (e.g., `AN_PTR_CAST` with a sentinel in `ir.inc`) is correct because it reinterprets the original variable's pointer/address directly without copying.

---

### Future Deliverable: Two SQLite Demos

We will implement two distinct test cases in the test suite to demonstrate the two styles of C-interop:
1. **`test_sqlite_crud_typed.pas` (Static Typing):** Employs explicit typenames parsed from the header (e.g., `var db: sqlite3; stmt: sqlite3_stmt;`).
2. **`test_sqlite_crud_autotyped.pas` (Auto-Typed):** Employs deferred static type inference (e.g., `var db: auto; stmt: auto;`) where typenames are locked in dynamically upon first assignment.

