program TestGenericFunc;

generic function Max<T>(A, B: T): T;
begin
  if A < B then Result := B else Result := A;
end;

generic function Min<T>(A, B: T): T;
begin
  if A > B then Result := B else Result := A;
end;

generic function Clamp<T>(V, Lo, Hi: T): T;
begin
  if V < Lo then Result := Lo
  else if V > Hi then Result := Hi
  else Result := V;
end;

generic procedure Swap<T>(var A, B: T);
var tmp: T;
begin
  tmp := A; A := B; B := tmp;
end;

specialize Max<Integer> as MaxIntF;
specialize Min<Integer> as MinInt;
specialize Clamp<Integer> as ClampInt;
specialize Swap<Integer> as SwapInt;

var x, y: Integer;
begin
  writeln(MaxIntF(3, 7));
  writeln(MaxIntF(10, 4));
  writeln(MinInt(3, 7));
  writeln(MinInt(10, 4));
  writeln(ClampInt(5, 1, 10));
  writeln(ClampInt(-3, 1, 10));
  writeln(ClampInt(15, 1, 10));
  x := 42; y := 99;
  SwapInt(x, y);
  writeln(x);
  writeln(y);
end.
