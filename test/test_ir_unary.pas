program test_ir_unary;
var i, j: Integer; b1, b2: Boolean;
begin
  i := 5;
  j := -i;
  writeln(j); { -5 }
  b1 := True;
  b2 := not b1;
  if b2 then
    writeln('FAIL')
  else
    writeln('OK');
end.
