program test_typeinfo_array_pointer;
{ TypeInfo(T) over named ARRAY types and the builtin non-ordinals.

  Arrays keep their own name table (ArrType*, FindArrayType) rather than the
  alias table, so they need their own TypeInfoReq category; ArrTypeIsDyn is the
  whole kind decision. `Pointer` and `Variant` are here for a different reason:
  this path used to keep a PRIVATE subset of the builtin-name table (the float
  family and the strings, nothing else), so TypeInfo(Pointer) and
  TypeInfo(Variant) were refused while SizeOf of the same names worked. It now
  defers to the one BuiltinTypeNameTk table, which is what
  devdocs/dev/normalise-dont-special-case.md asks for and what that function's
  own header comment says SizeOf had to learn.

  Kinds are FPC's TTypeKind ordinals, and all five rows were diffed against
  FPC 3.2.2 rather than recalled: 12 tkArray, 21 tkDynArray, 29 tkPointer,
  11 tkVariant. TArr2 is present because a MULTI-dimension array is still one
  tkArray, not a nested one. }
uses typinfo;
type
  TArr  = array[0..3] of Integer;
  TDyn  = array of Integer;
  TArr2 = array[1..2, 1..3] of Byte;
procedure S(p: PTypeInfo);
begin
  Writeln(p^.NamePtr^, ' ', p^.Kind);
end;
begin
  S(TypeInfo(TArr));
  S(TypeInfo(TDyn));
  S(TypeInfo(TArr2));
  S(TypeInfo(Pointer));
  S(TypeInfo(Variant));
end.
