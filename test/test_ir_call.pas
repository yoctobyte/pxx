program test_ir_call;

procedure PrintSum(a, b: Integer);
begin
  writeln(a + b);
end;

function Multiply(x, y: Integer): Integer;
begin
  Multiply := x * y;
end;

procedure AddOneRef(var val: Integer);
begin
  val := val + 1;
end;

var
  res, count: Integer;
begin
  PrintSum(10, 20); { 30 }
  
  res := Multiply(5, 6);
  writeln(res); { 30 }
  
  count := 41;
  AddOneRef(count);
  writeln(count); { 42 }
end.
