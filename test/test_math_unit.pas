program TestMathUnit;
uses math;
var
  a, b, val: Integer;
begin
  { Test external C functions }
  writeln(abs(-42));
  writeln(labs(-999));
  
  { Test pure Pascal math functions }
  writeln(Min(10, 20));
  writeln(Max(10, 20));
  writeln(Power(2, 8));
  writeln(Gcd(48, 18));
  writeln(Lcm(48, 18));
end.
