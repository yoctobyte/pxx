program aggrec;
type TPair = record A, B: Integer; end;
function MakePair(a, b: Integer): TPair;
begin
  Result.A := a;
  Result.B := b;
end;
function RecursivePair(n: Integer): TPair;
begin
  if n = 0 then begin Result := MakePair(10, 20); Exit; end;
  Result := MakePair(n, n*2);
end;
var p: TPair;
begin
  p := MakePair(3, 7);
  writeln(p.A, ' ', p.B);
  p := RecursivePair(0);
  writeln(p.A, ' ', p.B);
  p := RecursivePair(5);
  writeln(p.A, ' ', p.B);
end.
