program test_a_typeinfo_returns_one_shape_of_pointer;
{ TypeInfo returns ONE shape: a TTypeInfoHdr (Kind, NamePtr, DataPtr) for an
  enum too, and the SAME pointer for a plain alias as for its target. Every line
  matches fpc 3.2.2's output (fpc spells the name field `Name`; pxx's is
  `NamePtr`). Before 2026-11-19, an enum returned its bare blob, so Kind read an
  address and NamePtr crashed. An enum alias returned an Integer header, so
  GetEnumName crashed. A record alias returned a nameless header, which crashed
  its NamePtr reader.
  bug-a-typeinfo-does-not-return-one-shape-of-pointer
  (`TMyInt = Integer` answering Integer's own pointer is the separate
  bug-a-a-plain-type-alias-gets-its-own-rtti-blob-so-typeinfo-pointer-dispatch-misses.) }
{$mode objfpc}
uses typinfo;
type
  TColour = (red, green, blue);
  TMyColour = TColour;
  TRange1 = green..blue;
  TRec = record a, b: Integer; end;
  TMyRec = TRec;
  TMyInt = Integer;
begin
  WriteLn('enum kind ', Ord(PTypeInfo(TypeInfo(TColour))^.Kind), ' ', PTypeInfo(TypeInfo(TColour))^.NamePtr^);
  WriteLn('alias kind ', Ord(PTypeInfo(TypeInfo(TMyColour))^.Kind), ' ', PTypeInfo(TypeInfo(TMyColour))^.NamePtr^);
  WriteLn('alias same ', TypeInfo(TMyColour) = TypeInfo(TColour));
  WriteLn('enum name ', GetEnumName(TypeInfo(TColour), 1), ' ', GetEnumName(TypeInfo(TMyColour), 2), ' ', GetEnumName(TypeInfo(TRange1), 2));
  WriteLn('rec kind ', Ord(PTypeInfo(TypeInfo(TRec))^.Kind), ' ', PTypeInfo(TypeInfo(TRec))^.NamePtr^);
  WriteLn('recalias ', Ord(PTypeInfo(TypeInfo(TMyRec))^.Kind), ' ', PTypeInfo(TypeInfo(TMyRec))^.NamePtr^, ' ', TypeInfo(TMyRec) = TypeInfo(TRec));
  WriteLn('getenumvalue ', GetEnumValue(TypeInfo(TColour), 'blue'));
end.
