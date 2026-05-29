program test_float_literals;
{ Guards against float-literal lexing corruption. Each literal is cross-checked
  against a value computed by arithmetic, so a shared lexer error cannot mask
  the bug (as it did when comparing a wrong literal only against itself). }

var
  a, b: Double;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

begin
  { 3.5 = 7.0 / 2.0 }
  a := 3.5;
  b := 7.0 / 2.0;
  Check(a = b);

  { 2.5 = 5.0 / 2.0 }
  a := 2.5;
  b := 5.0 / 2.0;
  Check(a = b);

  { 100.125 = 801.0 / 8.0 }
  a := 100.125;
  b := 801.0 / 8.0;
  Check(a = b);

  { 3.5 is exactly halfway between 3 and 4 }
  a := 3.5;
  Check(a + a = 7.0);
  Check(a - 0.5 = 3.0);
  Check(a * 2.0 = 7.0);

  { fractional with integer part >= 2 (the class that was broken) }
  a := 12.25;
  b := 49.0 / 4.0;
  Check(a = b);
end.
