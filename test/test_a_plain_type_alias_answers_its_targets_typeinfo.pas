program test_a_plain_type_alias_answers_its_targets_typeinfo;
{ A PLAIN alias names the same type, so TypeInfo answers the target's own
  pointer and `if p = TypeInfo(Integer)` dispatch matches, by type name or
  through a variable declared with the alias. A distinct `= type Integer`
  keeps its own entry. Every line matches fpc 3.2.2.
  bug-a-a-plain-type-alias-gets-its-own-rtti-blob-so-typeinfo-pointer-dispatch-misses
  (Not here: fpc's TypeInfo(LongInt) = TypeInfo(Integer) synonym, which pxx keeps
  as two kinds under decide-typeinfo-scalar-name-spelling.) }
{$mode objfpc}{$H+}
uses typinfo;
type
  TMyInt = Integer;
  TMyLong = LongInt;
  TMyStr = string;
  TMyDbl = Double;
  TMyByte = Byte;
  TMyBool = Boolean;
  TDistinct = type Integer;
  TColour = (red, green);
  TMyColour = TColour;
  TRec = record a: Integer; end;
  TMyRec = TRec;
  TP = Pointer;
var m: TMyInt; s: TMyStr;
procedure Row(const lbl: string; same: Boolean); begin WriteLn(lbl, ' ', same); end;
begin
  Row('int    ', TypeInfo(TMyInt) = TypeInfo(Integer));
  Row('long   ', TypeInfo(TMyLong) = TypeInfo(LongInt));
  Row('str    ', TypeInfo(TMyStr) = TypeInfo(string));
  Row('dbl    ', TypeInfo(TMyDbl) = TypeInfo(Double));
  Row('byte   ', TypeInfo(TMyByte) = TypeInfo(Byte));
  Row('bool   ', TypeInfo(TMyBool) = TypeInfo(Boolean));
  Row('enum   ', TypeInfo(TMyColour) = TypeInfo(TColour));
  Row('rec    ', TypeInfo(TMyRec) = TypeInfo(TRec));
  Row('ptr    ', TypeInfo(TP) = TypeInfo(Pointer));
  Row('var m  ', TypeInfo(m) = TypeInfo(Integer));
  Row('var s  ', TypeInfo(s) = TypeInfo(string));
  Row('DISTINCT', TypeInfo(TDistinct) = TypeInfo(Integer));
end.
