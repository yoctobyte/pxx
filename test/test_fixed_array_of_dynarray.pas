program test_fixed_array_of_dynarray;

{ Regression for bug-setlength-array-element (case B): a FIXED array whose
  element is a named dynamic-array alias (`array[0..N] of TA`, TA = array of T).
  Each slot holds a pointer-sized dyn-array handle; SetLength / indexing /
  Length / whole-element assignment must all treat a[i] as a dynamic array. }

type
  TA  = array of Integer;
  TR  = record s: AnsiString; n: Integer; end;
  TRA = array of TR;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

procedure Local;   { proc-local: exercises the local frame path }
var a: array[0..2] of TA; i, j, s: Integer;
begin
  for i := 0 to 2 do
  begin
    SetLength(a[i], 3);
    for j := 0 to 2 do a[i][j] := i * 3 + j;
  end;
  SetLength(a[1], 5); a[1][4] := 100;   { grow }
  SetLength(a[0], 1);                    { shrink }
  s := 0;
  for i := 0 to 2 do
    for j := 0 to Length(a[i]) - 1 do s := s + a[i][j];
  Check(s = 133);
  Check(a[1][4] = 100);
  Check(Length(a[0]) = 1);
end;

var
  a, b: array[0..3] of TA;     { multi-name decl }
  r: array[0..2] of TRA;       { record element }
  i: Integer;
begin
  for i := 0 to 3 do begin SetLength(a[i], i + 1); a[i][0] := i * 10; end;
  Check(a[0][0] = 0);
  Check(a[3][0] = 30);
  Check(Length(a[0]) = 1);
  Check(Length(a[3]) = 4);

  SetLength(a[2], 5); a[2][4] := 99;
  Check((a[2][4] = 99) and (Length(a[2]) = 5));

  b[1] := a[3];                { whole dyn-array element assign }
  Check((b[1][0] = 30) and (Length(b[1]) = 4));

  SetLength(r[0], 2); r[0][1].s := 'hi'; r[0][1].n := 7;
  Check((r[0][1].s = 'hi') and (r[0][1].n = 7));

  Local;
end.
