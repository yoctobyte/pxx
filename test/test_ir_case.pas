program TestIRCase;
var
  I: Integer;
begin
  for I := 1 to 5 do
  begin
    case I of
      1, 2: writeln(12);
      3: writeln(3);
    else
      writeln(99);
    end;
  end;
end.
