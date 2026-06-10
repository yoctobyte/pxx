program arith;

{ i386 cross-target slice 2: integer globals, arithmetic, compares,
  while/if control flow, integer writeln. Output must be identical to the
  x86-64 build of this same program. }

var a, b, c: Integer;
begin
  a := 6;
  b := 7;
  c := a * b;
  writeln(c);
  writeln(a + b);
  writeln(a - b);
  writeln(b div a);
  writeln(b mod a);
  writeln(-c);
  c := 0;
  while a > 0 do
  begin
    c := c + a;
    a := a - 1;
  end;
  writeln(c);
  if b = 7 then writeln(111) else writeln(222);
  if (b > 10) or (a = 0) then writeln(333);
end.
