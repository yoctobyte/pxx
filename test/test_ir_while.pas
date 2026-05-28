program TestIRWhile;
var
  I: Integer;
begin
  I := 0;
  while I < 3 do
  begin
    I := I + 1;
  end;
  writeln(I);
end.
