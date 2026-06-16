program test_cross_const_alias;
{ Untyped string constants and dynamic-array type aliases. Byte-identical on every
  target. }
const
  Greeting = 'Hello';
  Suffix = '!';
type
  TIntList = array of Integer;
  TRec = record x: Integer; end;
  TRecList = array of TRec;
var
  s: AnsiString;
  a: TIntList;
  r: TRecList;
  i, sa, sr: Integer;
begin
  s := Greeting + ', World' + Suffix;
  writeln(s, ' len=', Length(s));
  SetLength(a, 6);
  for i := 0 to 5 do a[i] := i * i;
  sa := 0; for i := 0 to 5 do sa := sa + a[i];
  writeln('alist=', sa, ' len=', Length(a));
  SetLength(r, 4);
  for i := 0 to 3 do r[i].x := i + 10;
  sr := 0; for i := 0 to 3 do sr := sr + r[i].x;
  writeln('rlist=', sr, ' len=', Length(r));
end.
