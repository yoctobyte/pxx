program TestNot;
{ Regression: `not` is bitwise complement for integer operands (matches FPC),
  logical for Boolean. Previously `not` was always logical (xor bit 0), so
  `not 15` wrongly gave 14 instead of -16. }
var
  a: Int64;
  i: Integer;
  done: Boolean;
begin
  { integer operands -> bitwise complement (~x = -x-1) }
  a := not 0;   writeln(a);   { -1 }
  a := not 15;  writeln(a);   { -16 }
  i := 255;
  a := not i;   writeln(a);   { -256 }

  { Boolean operands stay logical }
  done := False;
  i := 0;
  while not done do begin Inc(i); if i >= 4 then done := True; end;
  writeln(i);                 { 4 }
  if not (i = 5) then writeln('ok');   { ok }
end.
