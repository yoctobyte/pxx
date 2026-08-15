program TestMathUnit;
{ math_ext is the C header holding the libc entry points (labs). math.pas
  names it in its own interface, but that is math.pas's namespace -- a program
  calling labs directly names it directly. }
uses math, math_ext;
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
