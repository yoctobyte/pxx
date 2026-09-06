program TestGenericFunc;

{ `specialize Max<Integer> as MaxIntF;` below is the specialization-ALIAS
  DECLARATION. Its SIBLING SPELLING is the parameterless CALL,
  `specialize F<T>` with no `()`, tested in
  test_a_parameterless_generic_routine_is_called_without_parentheses.pas.
  The two differ by exactly ONE TOKEN -- `as` here, `(` (or nothing) there --
  so the call-site predicate that recognises one is the predicate that must
  decline the other. Changing it on either side breaks the other side three
  phases downstream, with a diagnostic about the declaration section ending:
  that is what happened at eb2447470 and was fixed at 8d37fac6b. This file is
  where the breakage SHOWS; the reasoning lives in the sibling's header. }


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
