{ `High(SizeUInt)` was `undefined variable (SizeUInt)` while `SizeUInt(v)` cast
  correctly and `SizeOf(SizeUInt)` answered 8. ONE NAME, THREE DOORS, TWO RIGHT.

  The cast path and SizeOf ask BuiltinScalarTypeKind; High/Low and TypeInfo ask
  OrdinalNameToTk, and `sizeuint` was in the first table's nativeuint line and
  not the second's. BuiltinScalarTypeKind's own comment names that exact drift
  ("sizeint/sizeuint were in one and not the other") -- SizeInt had since been
  added to both and SizeUInt to only one, so the warning was half acted on and
  nothing failed loudly, because each door is correct for the names its own
  callers used.

  FOUND BY DIFFING THE TABLES, not by a failing program: OrdinalNameToTk is a
  strict subset of BuiltinScalarTypeKind (30 names of 51) with no name
  disagreeing, so a diff can only expose a MISSING one, and there was exactly
  one ordinal missing.

  ASSERTED AS RELATIONS, NOT CONSTANTS. SizeUInt is pointer-sized, so a row
  saying 18446744073709551615 would be an x86-64 fact and would fail on i386,
  arm32, riscv32 and xtensa -- the targets where a width bug actually lives and
  where nobody looks by default. Every row here says "this name answers what its
  synonyms answer", which is true on every target and still prints a different
  correct number on each.
  refactor-p-five-dispatch-sites-for-one-named-type-cast }
program test_sizeuint_answers_like_its_synonyms;
{$mode delphi}
var
  u: SizeUInt;
  v: Int64;
begin
  { High/Low through the door that did not know the name }
  WriteLn('high = nativeuint  ', High(SizeUInt) = High(NativeUInt));
  WriteLn('high = ptruint     ', High(SizeUInt) = High(PtrUInt));
  WriteLn('low  = nativeuint  ', Low(SizeUInt) = Low(NativeUInt));
  WriteLn('high <> sizeint    ', High(SizeUInt) <> QWord(High(SizeInt)));

  { ...and the doors that always knew it, so a fix that breaks THEM shows }
  WriteLn('sizeof = pointer   ', SizeOf(SizeUInt) = SizeOf(Pointer));
  WriteLn('sizeof = nativeuint', SizeOf(SizeUInt) = SizeOf(NativeUInt));
  v := -1;
  u := SizeUInt(v);
  WriteLn('cast = high        ', u = High(SizeUInt));

  { the signed twin, which was never broken -- the control for the whole file }
  WriteLn('sizeint = nativeint', High(SizeInt) = High(NativeInt));

  WriteLn('SIZEUINT SYNONYMS OK');
end.
