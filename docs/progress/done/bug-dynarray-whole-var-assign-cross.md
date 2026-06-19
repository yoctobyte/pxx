# Whole dynamic-array variable assignment (`b := a`) unsupported on i386 + aarch64

- **Type:** bug (compiler / codegen, cross-target)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (found while adding cross tests for the dynamic-array
  `Copy` intrinsic, feature-copy-intrinsic)

## Symptom

Assigning one dynamic-array variable to another (the whole-handle copy, not an
element store) is broken on two cross targets:

```pascal
var a, b: array of Integer;
begin
  SetLength(a, 3); a[0] := 5; a[1] := 6; a[2] := 7;
  b := a;            { i386: compile error; aarch64: SIGSEGV }
  Writeln(b[1]);     { x86-64: 6 / arm32: 6 }
end.
```

- **x86-64:** works.
- **arm32:** works.
- **i386:** `pascal26: error: target i386: arrays not yet supported` — the
  whole-array store routes through `IREmit386CheckScalarSym`
  (ir_codegen386.inc ~465), which refuses array symbols.
- **aarch64:** compiles, segfaults at runtime.

The IR is the same on every target: `b := a` lowers to `store_sym b, lea(a)`
(the source handle), a pointer-width handle copy. i386 rejects the array sym in
its scalar-store path; aarch64 mis-handles it at runtime.

## Impact

Any value-style dynamic-array API whose result is assigned to a variable is
limited to x86-64 + arm32. In particular the generic dynamic-array
`Copy(arr, index, count)` intrinsic (feature-copy-intrinsic) produces a fresh
`array of T` that the caller assigns — so `b := Copy(a, i, n)` inherits exactly
this gap. The `Copy` lowering itself is target-independent; only the trailing
whole-array assignment fails on i386/aarch64. The x86-64 self-host gate is
unaffected.

`test/test_dynarray_copy.pas` therefore runs in test-core (x86-64) and the arm32
cross suite only; once this is fixed, add it to the i386 + aarch64 cross suites.

## Direction

Give i386 (and aarch64) a real whole-dynamic-array assignment path: copy the
pointer-sized handle into the destination slot (with the dyn-array refcount
retain/release, like the managed-string publish), instead of routing it through
the scalar-ordinal store that refuses array syms. On i386 the handle is a single
4-byte slot value, so it is a plain pointer store plus refcount bookkeeping.

## Log
- 2026-06-19 — opened by track A. Isolated from the dynamic-array `Copy` cross
  tests: plain `b := a` reproduces it without `Copy`. i386 compile error +
  aarch64 segfault; x86-64 + arm32 fine.

## Resolution (2026-06-19) — FIXED

Both targets store the pointer-sized handle now:
- **i386:** `IR_STORE_SYM` gets a dynamic-array case before the scalar check —
  a plain 4-byte handle store (i386 dyn arrays are not refcounted here, so no
  retain/release needed). ir_codegen386.inc.
- **aarch64:** `EmitStoreVarA64` was storing `TypeSize(elementType)` (4 for
  `array of Integer`), truncating the 64-bit handle to 32 bits → bad pointer →
  segfault. Forced a full `TARGET_PTR_SIZE` store for dyn-array syms.
  ir_codegen_aarch64.inc.

`b := a` and `b := Copy(...)` now work on all four targets. `test_dynarray_copy.pas`
re-added to the i386 + aarch64 cross suites (was x86-64 + arm32 only); all 3 cross
suites output-identical to x86-64; self-host + cross-bootstrap byte-identical.
