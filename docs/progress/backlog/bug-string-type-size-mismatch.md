# String type size mismatch in TypeSize vs codegen copies

- **Type:** bug
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20
- **Relation:** surfaced when implementing dynamic arrays of `string` in TListBox and TComboBox in stdctrls.pas.

## Problem

Under the compiler configuration, `TypeSize(tyString)` returns `8`, indicating a pointer-sized slot. However, the keyword `string` represents `tyString` (the 264-byte inline unmanaged string). When assigning or copying `string` values, the code generator emits a copy of 264 bytes. 

When `string` is used as an element type in dynamic arrays (e.g. `array of string`) or as fields in records, the compiler calculates the element stride or field offset based on `TypeSize(tyString) = 8`. But when elements are assigned (e.g. `arr[i] := s`), the compiler generates a copy of 264 bytes starting at `arr + i * 8`. This results in overlapping copies and corrupts/clobbers adjacent elements in the array/record.

## Reproduction

```pascal
program repro;
var
  a: array of string;
begin
  SetLength(a, 3);
  a[0] := 'Apple';   // copies 264 bytes to a[0] (offset 0), overlapping a[1] and a[2]
  a[1] := 'Banana';  // copies 264 bytes to a[1] (offset 8), clobbering most of a[0]
  a[2] := 'Cherry';  // copies 264 bytes to a[2] (offset 16), clobbering most of a[1]
  writeln(a[0]);     // prints blanks/garbage
  writeln(a[1]);     // prints blanks/garbage
  writeln(a[2]);     // prints Cherry (which was written last)
end.
```

## Root cause

In `compiler/symtab.inc`, `TypeSize(tyString)` returns `8`. In `compiler/ir_codegen.inc`, the stride for array elements of type `tyString` is calculated using `TypeSize(tyString)`, resulting in a stride of 8 bytes. But assignments of `tyString` are lowered to copy the full inline-string buffer size (264 bytes).

Furthermore, when `PXX_MANAGED_STRING` is defined, the keyword `string` still maps to `tyString` rather than `tyAnsiString`.

## Workaround

Use `AnsiString` instead of `string` for arrays or complex structures when managed strings are enabled (`PXX_MANAGED_STRING`).

## Fix direction

If `PXX_MANAGED_STRING` is defined, the keyword `string` should map to `tyAnsiString` (which has a size of 8 bytes and is correctly reference counted). If `PXX_MANAGED_STRING` is not defined, `TypeSize(tyString)` should return `264` to match the actual memory size of `tyString` in all stride and offset calculations.

## Log
- 2026-06-20 — opened. Discovered while testing TListBox and TComboBox items.
