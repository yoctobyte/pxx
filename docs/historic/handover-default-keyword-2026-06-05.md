# Handover: `default` Keyword Implementation - 2026-06-05

> **STATUS: DONE (2026-06-05).** `default` assignment is implemented and
> covered by `test/test_default_keyword.pas`. This file is archived as the
> original implementation prompt.

This handover document defines the design and implementation plan for adding the `default` keyword to the compiler. It is designed to act as a zero-initializer for any type, particularly useful for clearing or resetting variable state (e.g., `db := default;`).

## Goal
Support assigning the `default` keyword to a variable, resetting its state to its type's default value:
*   **Ordinals & Pointers** (Integer, Boolean, PChar, Pointer, Char, etc.): resets to `0` / `nil`.
*   **Floats** (Single, Double, Extended): resets to `0.0`.
*   **Strings** (AnsiString): resets to empty string `''` (which handles memory release and zero-initialization).
*   **Managed Records/Arrays**: releases current resources and zero-initializes the memory footprint.

## Implementation Steps

### 1. Lexer & Token Setup
*   **File:** `compiler/defs.inc`
    Add `tkDefault` to the `TTokenKind` enum.
*   **File:** `compiler/blexer.inc`
    In `BKeyword`, register the string `'default'` mapping to `tkDefault`.

### 2. AST / Parser Integration
*   **File:** `compiler/defs.inc`
    Add the AST node kind `AN_DEFAULT` to the AST node types if applicable.
*   **File:** `compiler/parser.inc`
    *   In `ParsePrimary`, when `CurTok.Kind = tkDefault`, parse it, advance the lexer (`Next`), and return `AllocNode(AN_DEFAULT)`.
    *   Ensure `AN_DEFAULT`'s type is initially unresolved (`tyUnknown`), waiting to be coerced/inferred from its target context.

### 3. Type Resolution and Inference Gating
*   **File:** `compiler/parser.inc`
    *   During assignment type checking (`ResolveNodeTk` / expression parsing):
        *   If the target (LHS) is explicitly typed, set `ASTTk[AN_DEFAULT]` to match the LHS type.
        *   If the target (LHS) is `auto` and has **not** been inferred yet (e.g. `var x := default;`), throw a compile-time error: `Cannot infer type from default. Specify type explicitly (e.g. var x: Integer := default;).`
        *   If the target (LHS) is `auto` but **has** already had its type inferred previously, set the type of `AN_DEFAULT` to the LHS's inferred type.

### 4. IR Lowering
*   **File:** `compiler/ir.inc`
    In `LowerAssign` (or the equivalent assignment lowering path):
    If the RHS node is `AN_DEFAULT`:
    *   **Ordinal/Pointer:** Lower it as a constant assignment of `0` (similar to `x := 0` or `x := nil`).
    *   **Float/Real:** Lower it as a constant assignment of `0.0` (similar to `x := 0.0`).
    *   **String:** Lower it as a string assignment to literal empty string `''` (which calls the proper compiler string runtime helpers to release the existing string from memory and zero out the handle).
    *   **Managed Record/Array:** Lower it as a zeroing operation (similar to `AN_VAR_DECL` zeroing).

## Verification Gating
All changes must be verified via:
1.  `make bootstrap` (fixed-point compiler self-hosting check).
2.  `make test` (the regression test suite).
3.  Add a new test file: `test/test_default_keyword.pas` to exercise ordinal, pointer, string, and record default assignments.

---

# Prompt for the Incoming Agent (Sis AI)

Copy and run the prompt below to implement this feature:

```text
Please implement the `default` keyword feature in the compiler. 
The feature allows assigning `default` to variables to reset them to their default state (0, nil, '', or zeroed memory).

Refer to the archived design file `docs/historic/handover-default-keyword-2026-06-05.md` for full implementation details.
Follow these steps:
1. Add `tkDefault` to `defs.inc` and register `'default'` in `blexer.inc`'s keyword list.
2. Define AST node kind `AN_DEFAULT` (if needed, check existing AST node kinds in defs.inc / parser.inc) and parse it in `ParsePrimary`.
3. Resolve the type of `AN_DEFAULT` based on the target (LHS) of the assignment. Raise a compile-time error if type inference is impossible (e.g. `var x := default;`).
4. Lower `LHS := default` in `compiler/ir.inc` appropriately depending on the LHS type (constant 0, 0.0, empty string, or zeroed memory).
5. Build and verify using the standard compiler bootstrap gate: `make bootstrap`, `make test`, `make test-nilpy`, `make fpc-check` all green and byte-identical.
6. Create a test file `test/test_default_keyword.pas` testing default assignments for Integer, string, Pointer, and a managed record.

End your commit message with the Co-Authored-By trailer for the agent that actually did the work.
```
