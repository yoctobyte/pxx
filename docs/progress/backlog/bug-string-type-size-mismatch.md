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

## Investigation 2026-06-20 (design clarified; fix is a multi-part arc)

Reproduced + clarified with the user. Intended model:
- `string` = the managed AnsiString in managed-string mode (the DEFAULT;
  `-uPXX_MANAGED_STRING` selects frozen). Today the bare `string` keyword
  (parser.inc ParseTypeKind `tkString_T`) always returns tyString, ignoring the
  mode — only the `ansistring` keyword honors it. THIS is the gap.
- `string[N]` = a frozen fixed-length string (already right-sizes; e.g. bss ~64).
- `shortstring` = the explicit unmanaged short string (255). NOT currently a real
  keyword — it falls through and Length()/writeln on it return garbage.
- The 8 MB `STRING_CAP` is wired as the frozen-string GLOBAL var default size
  (symtab.inc:1419) AND as the compiler's token buffer — same constant, two jobs.
  A frozen bare-`string` global reserves 8 MB. Relic; should be ~255 via a
  separate small constant.

Tried the one-line flip (tkString_T -> tyAnsiString under PXX_MANAGED_STRING,
keeping `string[N]` frozen): `array of string` then works and the GUI bug is
fixed, BUT `make test` SEGFAULTS — `Str(x, s)` / `Val` and likely other string
builtins do not support AnsiString as the `string` type. So the global flip
surfaces real incompleteness in the managed-string path; reverted to keep master
green.

So this is a multi-step arc, not a one-liner:
1. (this) Either flip `string`->AnsiString in managed mode AND make Str/Val (+
   any frozen-buffer-assuming builtin) work with AnsiString; OR take a per-use
   path: only ARRAY/DYNARRAY/RECORD-FIELD `string` elements resolve to
   AnsiString, leaving scalar `var s: string` frozen (scalar Str/Val unaffected).
   The per-use path fixes array-of-string / the GUI without the Str/Val breakage.
2. `shortstring` -> real frozen-255 keyword (depends on the frozen-sized-string
   output bug below).
3. Frozen-string global default size: STRING_CAP(8MB) -> a small DEFAULT_STR_CAP.
4. Separate pre-existing bug: writeln/Length of a frozen SIZED string
   (`string[N]` / current `shortstring`) returns garbage (a code address). Plain
   `var s: string` frozen writeln works; the sized path does not.
5. User's idea: an internal `tyFixedString` kind to disambiguate the frozen
   fixed/short string from managed AnsiString (today tyString is overloaded). A
   clean refactor that likely also fixes (4).

The cross-link to bug-rtti-offset-static-array (#4): same string-size model; a
large `array[0..255] of string` field inherits the per-element sizing decision.

## Per-use quick fix DONE 2026-06-20 (Track B unblocked; full arc still open)

ParseTypeKind `tkString_T`: a bare `string` whose preceding token is `of` (an
aggregate element, `array of string` / `array[..] of string`) is promoted to
managed AnsiString in managed mode. Scalar `string` (preceded by `:`) stays
frozen, so Str/Val and other frozen-buffer builtins are untouched (that was the
make-test segfault). `string[N]` stays frozen fixed. `array of string` and class
fields like `FItems: array of string` now work. Byte-identical self-host,
make test green. test/test_array_of_string.pas added.

STILL OPEN (the full arc): scalar `string`->AnsiString flip + Str/Val managed
support, `shortstring` keyword, STRING_CAP->small default, frozen-sized-string
writeln bug, and the `tyFixedString` disambiguation.
