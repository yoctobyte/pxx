program test_ir_binops;

var
  a, b: Integer;
  u1, u2: LongWord;
  cond1, cond2: Boolean;
begin
  { Signed div/mod }
  a := -17;
  b := 5;
  writeln(a div b); { -3 }
  writeln(a mod b); { -2 }
  
  { Unsigned div/mod }
  u1 := 17;
  u2 := 5;
  writeln(u1 div u2); { 3 }
  writeln(u1 mod u2); { 2 }
  
  { Bitwise/logical AND / OR }
  a := 12; { 1100 }
  b := 10; { 1010 }
  writeln(a and b); { 8 }
  writeln(a or b);  { 14 }
  
  cond1 := True;
  cond2 := False;
  if cond1 and cond2 then writeln(1) else writeln(0); { 0 }
  if cond1 or cond2 then writeln(1) else writeln(0);  { 1 }
  
  { Shifts (shr) }
  a := 100;
  writeln(a shr 2); { 25 }
end.
