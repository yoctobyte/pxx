program test_ir_codegen;
var i, sum: Integer;
begin
  sum := 0;
  for i := 1 to 5 do
  begin
    sum := sum + i;
  end;
  writeln(sum);
  if sum = 15 then
    writeln('OK')
  else
    writeln('FAIL');
end.
