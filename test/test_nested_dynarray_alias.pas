program test_nested_dynarray_alias;

{ A named dynamic-array type used as the ELEMENT of an outer dynamic array
  (`array of TA` where `TA = array of T`) must compose its dynamic depth, just
  like the literal `array of array of T`. The alias lives in the ArrType table,
  not the scalar alias table, so the var-section parser resolves and composes it
  before falling through to ParseTypeKind (which would otherwise drop the
  dynamic dimension and flatten the element to its base type).
  Regression for bug-setlength-array-element (case A: dynamic outer). }

type
  TIntArr = array of Integer;
  TRec    = record x, y: Integer; end;
  TRecArr = array of TRec;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

var
  m: array of TIntArr;     { = array of array of Integer }
  r: array of TRecArr;     { dyn alias of record element }
  i, j: Integer;

begin
  SetLength(m, 3);
  Check(Length(m) = 3);
  SetLength(m[0], 2);
  SetLength(m[1], 4);
  Check(Length(m[0]) = 2);
  Check(Length(m[1]) = 4);
  for i := 0 to 1 do
    for j := 0 to Length(m[i]) - 1 do
      m[i][j] := i * 10 + j;
  Check(m[0][0] = 0);
  Check(m[1][3] = 13);

  { Grow a sub-array: prefix preserved, new slots zero. }
  SetLength(m[0], 4);
  Check(m[0][1] = 1);
  Check(m[0][3] = 0);

  { Record element through the alias. }
  SetLength(r, 2);
  SetLength(r[0], 3);
  r[0][1].x := 42;
  r[0][1].y := 7;
  Check(r[0][1].x = 42);
  Check(r[0][1].y = 7);
end.
