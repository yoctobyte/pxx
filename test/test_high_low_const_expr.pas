program test_high_low_const_expr;
{ High/Low of ordinal types in CONSTANT expressions — array bounds, const
  decls, composition with const operators (bug-pascal-high-low-in-const-expr;
  ZenGL's zgl_types.pas bound).

  …and of a named SUBRANGE, which used to answer the BASE type's bounds:
  `TDigit = 0..9` gave -2147483648/2147483647, so the idiomatic
  `for i := Low(T) to High(T)` ran four billion times instead of ten. Both the
  constant-expression resolver and the expression one had to learn it — they
  are one concept in two functions.
  bug-a-low-high-of-a-named-subrange-answer-the-base-type }
type
  TE = (eA, eB, eC);
  TDigit  = 0..9;
  TLetter = 'a'..'e';
  TNeg    = -5..5;
  TSmall = array[0..High(Byte)] of Byte;
  TBig = array[0..High(LongWord) shr 24] of Byte;   { 0..255 }
const
  HB = High(Byte);
  LI = Low(SmallInt);
  HE = High(TE);
  DLo = Low(TDigit);      { a subrange bound folded in a CONST decl }
  DHi = High(TDigit);
var
  s: TSmall;
  b: TBig;
  i, n: Integer;
  c: Char;
begin
  writeln(SizeOf(TSmall));
  writeln(SizeOf(TBig));
  writeln(HB, ' ', LI, ' ', Ord(HE));
  writeln(High(LongWord) shr 1 - 1);
  s[High(Byte)] := 7; writeln(s[255]);
  b[0] := 1; writeln(b[0]);
  writeln(DLo, ' ', DHi);
  writeln(Low(TDigit), ' ', High(TDigit), ' ', Low(TNeg), ' ', High(TNeg));
  writeln(Low(TLetter), ' ', High(TLetter));
  n := 0;
  for i := Low(TDigit) to High(TDigit) do n := n + 1;
  writeln(n);
  n := 0;
  for c := Low(TLetter) to High(TLetter) do n := n + 1;
  writeln(n);
end.
