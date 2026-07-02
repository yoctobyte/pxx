{ SPDX-License-Identifier: MPL-2.0 }
{ Regression: ordinal->enum typecast TEnum(intExpr) resolved as "undefined
  variable (TEnum)" while enum->ordinal Integer(e) worked.
  See bug-integer-to-enum-typecast-undefined-variable. }
program TestEnumCast;

type
  TColor = (cWhite, cBlack);
  TPiece = (pNone, pPawn, pKnight, pBishop, pRook, pQueen, pKing);

function PickIdx: Integer;
begin
  PickIdx := 3;
end;

var
  c: TColor;
  p: TPiece;
  i: Integer;
begin
  { cast a variable }
  i := 1;
  c := TColor(i);
  writeln(Ord(c));
  { cast a constant expression }
  p := TPiece(2 + 3);
  writeln(Ord(p));
  { cast a function-call result }
  p := TPiece(PickIdx);
  writeln(Ord(p));
  { cast an arithmetic expression over Ord (the chess idiom) }
  c := TColor(1 - Ord(c));
  writeln(Ord(c));
  { round-trip: enum->ordinal still works }
  i := Integer(p);
  writeln(i);
end.
