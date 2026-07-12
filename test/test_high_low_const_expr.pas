program test_high_low_const_expr;
{ High/Low of ordinal types in CONSTANT expressions — array bounds, const
  decls, composition with const operators (bug-pascal-high-low-in-const-expr;
  ZenGL's zgl_types.pas bound). }
type
  TE = (eA, eB, eC);
  TSmall = array[0..High(Byte)] of Byte;
  TBig = array[0..High(LongWord) shr 24] of Byte;   { 0..255 }
const
  HB = High(Byte);
  LI = Low(SmallInt);
  HE = High(TE);
var
  s: TSmall;
  b: TBig;
begin
  writeln(SizeOf(TSmall));
  writeln(SizeOf(TBig));
  writeln(HB, ' ', LI, ' ', Ord(HE));
  writeln(High(LongWord) shr 1 - 1);
  s[High(Byte)] := 7; writeln(s[255]);
  b[0] := 1; writeln(b[0]);
end.
