{ %FAIL-style negative: a reference-counted type in a VARIANT BRANCH.

  The storage is shared with the other branches, so nothing can know which
  finaliser to run, and fpc refuses it ("Data types which require
  initialization/finalization cannot be used in variant records").

  THIS FILE EXISTS BECAUSE THE REFUSAL USED TO BE ACCIDENTAL. The variant-part
  field parser simply had no dynamic-array arm, so this program failed with
  `expected '[' before 'of'` -- a grammar complaint that happened to land on the
  right answer. Merging that parser into the shared one gave it the arm, so the
  refusal had to become deliberate or the merge would have quietly ADDED a
  construct fpc rejects. A refusal nobody asserts is a refusal that disappears
  the next time its accidental cause does.
  refactor-p-the-field-declaration-parser-exists-twice }
program test_dynarray_in_a_variant_part_refused;
{$mode objfpc}{$H+}
type
  TV = record
    case Integer of
      0: (x: Integer);
      1: (d: array of Integer);
  end;
var v: TV;
begin
  WriteLn(SizeOf(v));
end.
