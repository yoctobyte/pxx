program test_named_fixed_array_of_a_dynamic_array;
{ A FIXED array whose ELEMENT is a named DYNAMIC array, reached through both
  spellings of the same type:

    type TRow = array of Integer;
         TFD  = array[0..1] of TRow;      { the NAMED spelling }
    var  f: TFD;
         g: array[0..1] of TRow;          { the INLINE spelling }

  Each slot holds a pointer-sized dyn-array HANDLE. The named spelling used to
  lose that (the array-type table had no ArrTypeElemDynDepth), so
  `SetLength(f[0], 1)` was refused with `SetLength expects an array variable in
  IR codegen` while the identical inline declaration compiled. Passing either
  form to an open array then copied only half the slots, because the copy-in
  sized elements by the ROW's base type. Every row is checked against
  `fpc -Mobjfpc`. }

type
  TRow  = array of Integer;
  TStrs = array of string;
  TFD   = array[0..1] of TRow;
  TFS   = array[0..1] of TStrs;
  TFD3  = array[1..3] of TRow;      { a non-zero low bound }

var
  fails: Integer;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got = want then Writeln(what, ' ok')
  else begin Writeln(what, ' FAIL got=', got, ' want=', want); Inc(fails); end;
end;

procedure ChkS(const what, got, want: AnsiString);
begin
  if got = want then Writeln(what, ' ok')
  else begin Writeln(what, ' FAIL got=[', got, '] want=[', want, ']'); Inc(fails); end;
end;

{ the named fixed type as a parameter, and as an open array }

procedure ByNamed(const m: TFD);
begin
  Chk('named.p.len0', Length(m[0]), 2);
  Chk('named.p.e01',  m[0][1],      2);
  Chk('named.p.e10',  m[1][0],      3);
end;

procedure ByOpen(const m: array of TRow);
var i, j, sum: Integer;
begin
  Chk('open.p.len',  Length(m),    2);
  Chk('open.p.len0', Length(m[0]), 2);
  Chk('open.p.len1', Length(m[1]), 1);
  sum := 0;
  for i := 0 to High(m) do
    for j := 0 to High(m[i]) do sum := sum + m[i][j];
  Chk('open.p.sum',  sum,          6);
end;

var
  f: TFD;
  g: array[0..1] of TRow;
  s: TFS;
  t: TFD3;
  i: Integer;

begin
  fails := 0;

  { the NAMED spelling: declare, SetLength each row, index it }
  SetLength(f[0], 2); f[0][0] := 1; f[0][1] := 2;
  SetLength(f[1], 1); f[1][0] := 3;
  Chk('named.len0', Length(f[0]), 2);
  Chk('named.len1', Length(f[1]), 1);
  Chk('named.e01',  f[0][1],      2);
  Chk('named.e10',  f[1][0],      3);
  Chk('named.high', High(f[0]),   1);

  { the INLINE spelling of the same type must agree }
  SetLength(g[0], 2); g[0][0] := 1; g[0][1] := 2;
  SetLength(g[1], 1); g[1][0] := 3;
  Chk('inline.len0', Length(g[0]), 2);
  Chk('inline.e01',  g[0][1],      2);
  Chk('inline.e10',  g[1][0],      3);

  ByNamed(f);
  ByOpen(f);
  ByOpen(g);

  { growing a row after it has been read, and rewriting through the handle }
  SetLength(f[1], 3); f[1][2] := 9;
  Chk('regrow.len', Length(f[1]), 3);
  Chk('regrow.e12', f[1][2],      9);
  Chk('regrow.e10', f[1][0],      3);

  { a managed element base type }
  SetLength(s[0], 2); s[0][0] := 'aa'; s[0][1] := 'bb';
  SetLength(s[1], 1); s[1][0] := 'cc';
  Chk ('str.len0', Length(s[0]), 2);
  ChkS('str.e01',  s[0][1],      'bb');
  ChkS('str.e10',  s[1][0],      'cc');

  { a non-zero low bound on the outer fixed array }
  for i := 1 to 3 do
  begin
    SetLength(t[i], i);
    t[i][i - 1] := i * 10;
  end;
  Chk('lo1.len1', Length(t[1]), 1);
  Chk('lo1.len3', Length(t[3]), 3);
  Chk('lo1.e1',   t[1][0],      10);
  Chk('lo1.e3',   t[3][2],      30);

  if fails = 0 then Writeln('ALL OK') else Writeln('FAILURES: ', fails);
end.
