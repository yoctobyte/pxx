program test_forin_deref_ptr_array;
{$mode objfpc}{$H+}
{ `for x in p^` where p: ^array[0..N] of T.

  Every bare-name for-in arm requires the next token to be `do`, and `p` is
  followed by `^`, so a deref fell through to the general container-EXPRESSION
  path -- which handled a class with GetEnumerator and a dyn-array value and
  then gave up. That is why the refusal reads "not a generator, enum type, or
  iterable variable" and not ParseForInNodeAST's own message: it never reached
  that function.

  NOT materialised into a hidden local, which is the move the two arms above it
  make. For a dyn array that copies a handle and still aliases; a static pointee
  would be copied WHOLE, and the `aliased=` row below is what holds that
  decision in place -- it writes through the pointer BEFORE iterating and the
  sum must include the new value, which a private copy would miss.

  A NON-ZERO low bound is handled, and the `lo1`/`lo5`/`loneg` rows are the
  ones that would silently pass on a broken build if they were not compared
  against the direct spelling. The bound is answered by TWO mechanisms here:
  `a1[1]` builds AN_INDEX(AN_IDENT, 1) and IR lowering subtracts the bound from
  Syms[].ConstVal, while `p1^[1]` builds AN_INDEX(AN_DEREF, 1 - 1) because the
  PARSER folds it in -- ir.inc's `lo` ladder has an AN_IDENT arm and an
  AN_FIELD arm and no deref arm. The loop builder synthesises its AN_INDEX
  without the parser, so it got neither: array[1..4] holding 11 22 33 44
  iterated as `22 33 44 4310536`. It now emits the subtraction itself, matching
  the parser for this shape.
  bug-p-for-in-over-a-dereferenced-pointer-to-array-is-refused }
type
  TArr = array[0..3] of Integer;
  PArr = ^TArr;
  TStr = array[0..2] of AnsiString;
  PStr = ^TStr;
  TLo1 = array[1..4] of Integer;  PLo1 = ^TLo1;
  TLo5 = array[5..7] of Integer;  PLo5 = ^TLo5;
  TNeg = array[-2..2] of Integer; PNeg = ^TNeg;
var
  a: TArr; p: PArr; x, s: Integer;
  sa: TStr; ps: PStr; w: AnsiString; acc: AnsiString;
  lo1: TLo1; p1: PLo1; lo5: TLo5; p5: PLo5; neg: TNeg; pn: PNeg;
begin
  a[0] := 0; a[1] := 10; a[2] := 20; a[3] := 30;
  p := @a;
  Write('direct=');
  for x in a do Write(x, ' ');
  WriteLn;
  Write('deref=');
  for x in p^ do Write(x, ' ');
  WriteLn;
  s := 0;
  for x in p^ do s := s + x;
  WriteLn('sum=', s);
  p^[2] := 99;
  s := 0;
  for x in p^ do s := s + x;
  WriteLn('aliased=', s);
  { non-zero and NEGATIVE low bounds, each against the direct spelling }
  lo1[1] := 11; lo1[2] := 22; lo1[3] := 33; lo1[4] := 44; p1 := @lo1;
  Write('lo1direct=');
  for x in lo1 do Write(x, ' ');
  WriteLn;
  Write('lo1deref=');
  for x in p1^ do Write(x, ' ');
  WriteLn;
  lo5[5] := 55; lo5[6] := 66; lo5[7] := 77; p5 := @lo5;
  Write('lo5deref=');
  for x in p5^ do Write(x, ' ');
  WriteLn;
  for x := -2 to 2 do neg[x] := x * 100;
  pn := @neg;
  Write('negderef=');
  for x in pn^ do Write(x, ' ');
  WriteLn;
  sa[0] := 'a'; sa[1] := 'b'; sa[2] := 'c';
  ps := @sa;
  acc := '';
  for w in ps^ do acc := acc + w;
  WriteLn('managed=', acc);
end.
