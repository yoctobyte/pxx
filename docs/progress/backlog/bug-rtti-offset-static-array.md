# RTTI offset corruption when class/record definitions contain large static arrays

- **Type:** bug
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20
- **Relation:** surfaced during PCL refactoring of TListBox/TComboBox in stdctrls.pas.

## Problem

When a class or record definition contains a large static array field (for example, `array[0..255] of string`), the compiler's generated RTTI / type descriptor offset calculation becomes corrupted, leading to runtime segmentation faults or offset mismatches.

## Reproduction

Declaring the following structure inside a class or record:

```pascal
type
  TListBox = class(TWinControl)
  private
    FItems: array[0..255] of string;
    FCount: Integer;
  end;
```

This layout leads to RTTI descriptor corruptions or invalid stack/heap layouts when accessing fields located after the static array, or when generating type descriptors for the class.

## Root cause

The compiler calculates fixed field offsets for RTTI generation and structure layouts. For large static arrays (especially arrays of complex types like `string`), the size calculation or alignment logic in the RTTI generation phase fails to account for the full size of the array field, resulting in corrupted type offsets.

## Workaround

Declare dynamic arrays (`array of string`) instead of large static arrays, and initialize them in the constructor via `SetLength(FItems, 256)`. Since dynamic arrays are represented as 8-byte pointer handles, this completely avoids the compiler's static array field size/offset mismatch bug.

## Fix direction

The compiler's RTTI/layout generation in `compiler/symtab.inc` and `compiler/rtti_emit.inc` should be corrected to properly calculate and propagate the size of static array fields when generating class and record descriptors.

## Log
- 2026-06-20 — opened. Discovered while implementing TListBox/TComboBox.
