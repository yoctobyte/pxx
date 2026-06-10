program test_varparam;

procedure ModifyInt(var x: Integer);
begin
  x := x + 10;
end;

procedure ModifyChar(var c: Char);
begin
  c := 'B';
end;

procedure ModifyBool(var b: Boolean);
begin
  b := not b;
end;

procedure TestAll(var x: Integer; var c: Char; var b: Boolean);
begin
  ModifyInt(x);
  ModifyChar(c);
  ModifyBool(b);
end;

var
  x: Integer;
  c: Char;
  b: Boolean;
begin
  x := 42;
  c := 'A';
  b := true;
  
  TestAll(x, c, b);
  
  writeln(x);
  writeln(c);
  writeln(b);
end.
