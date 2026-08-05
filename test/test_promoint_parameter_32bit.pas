program test_promoint_parameter_32bit;
{ Regression: a PromoInt PARAMETER on a 32-bit target, where PromoInt is the
  8-byte tyPromoInt32.

  The by-ref promotion used to be restricted to tyPromoInt64 because extending
  it to 32-bit made `n shr 4` on a parameter HANG. The cause was not the
  parameter machinery at all: promocore's SlotInt does `Int64(w^)` with
  `w: ^NativeInt`, i.e. an explicit Int64 cast of a NativeInt — which on a
  32-bit target reinterpreted 8 bytes instead of sign-extending 4
  (bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit). So the
  inline payload came back with a garbage high half, PromoShiftCount returned a
  huge count, and BShr's `for i := 1 to k` doubling loop spun forever.

  With that fixed the restriction is unnecessary, so the arm now covers both
  widths. The operators exercised here are deliberately the ones the ticket
  named as hanging — shr/and/div/mod, the ones that box their right operand —
  not just the arithmetic that always worked.
  bug-a-promoint-parameter-32bit-by-ref-indirection-hangs }
function shifted(n: PromoInt): PromoInt; begin Result := n shr 4; end;
function masked(n: PromoInt): PromoInt;  begin Result := n and 255; end;
function divd(n: PromoInt): PromoInt;    begin Result := n div 7; end;
function modd(n: PromoInt): PromoInt;    begin Result := n mod 7; end;
function summed(n: PromoInt): PromoInt;  begin Result := n + 7; end;
function scaled(n: PromoInt): PromoInt;  begin Result := n * 3; end;
function mutate(n: PromoInt): PromoInt;  begin n := n + 1; Result := n; end;
var p, big: PromoInt; i: Integer;
begin
  p := 256;
  writeln(shifted(p)); writeln(masked(p)); writeln(divd(p)); writeln(modd(p));
  writeln(summed(p));  writeln(scaled(p)); writeln(mutate(p));
  writeln(p);                              { mutate must NOT touch the caller }
  big := 1;
  for i := 1 to 30 do big := big * 10;     { heap tier, past 2^63 }
  writeln(shifted(big));
  writeln(divd(big));
  writeln('OK');
end.
