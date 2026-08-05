program test_promoint_arg_literal_and_result;
{ Regression: a PromoInt PARAMETER must accept a LITERAL and a CALL RESULT, not
  only a named variable.

  Two different errors for one gap: `f(12)` was "no overload matches / argument
  types: (Integer)" because TypesCompatible knew promo-arg -> integer-param but
  not the reverse; `f(g())` was "by-reference argument must be a variable"
  because a promo param is by-ref for ABI and the lvalue check had no exemption
  for it — though IRLowerCallArg copies into a hidden temp exactly as it does
  for a by-value record, which the same check already exempts.

  Fixed by adding the reverse TypesCompatible direction, exempting promo params
  in the lvalue check, and boxing an ordinal argument through PXXPromoFromInt
  (the same lowering `p := 12` uses). Values verified against Python.
  bug-a-promoint-parameter-rejects-literals-and-call-results }
function f(n: PromoInt): PromoInt; begin Result := n * 2; end;
function fact(n: Integer): PromoInt;
var i: Integer;
begin
  Result := 1;
  for i := 2 to n do Result := Result * i;
end;
{ an ordinary Integer overload must NOT be hijacked by the new rule }
function pick(n: Integer): string; begin Result := 'int'; end;
function pick(s: string): string;  begin Result := 'str'; end;
var p: PromoInt; k: Int64;
begin
  writeln(f(12));                 { literal }
  writeln(f(-5));                 { negative literal }
  writeln(f(fact(20)));           { call result, big }
  p := 7; writeln(f(p));          { variable }
  k := 1000000; writeln(f(k));    { Int64 variable }
  writeln(f(3 + 4));              { expression }
  writeln(f(f(3)));               { nested }
  writeln(pick(1), pick('x'));    { overloads still resolve correctly }
  writeln(fact(25));              { 25! — well past 2^63 }
  writeln('OK');
end.
