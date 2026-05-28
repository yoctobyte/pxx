program TestIRFor;
var
  I, Sum: Integer;
begin
  Sum := 0;
  for I := 1 to 5 do
  begin
    Sum := Sum + I;
  end;
  writeln(Sum);

  Sum := 0;
  for I := 5 downto 1 do
  begin
    Sum := Sum + I;
  end;
  writeln(Sum);
end.
