program test_cross_string_cow;

function LowerCaseCopy(const s: AnsiString): AnsiString;
var
  i: Integer;
  res: AnsiString;
begin
  res := s;
  for i := 1 to Length(res) do
    if res[i] in ['A'..'Z'] then
      res[i] := Chr(Ord(res[i]) + 32);
  LowerCaseCopy := res;
end;

var
  x, y: AnsiString;
begin
  x := 'HeapMmap';
  y := LowerCaseCopy(x);
  writeln(y);
  x[1] := 'Z';
  writeln(x);
end.
