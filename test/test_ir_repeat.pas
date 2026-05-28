program TestIRRepeat;
var
  I: Integer;
begin
  I := 0;
  repeat
    I := I + 1;
  until I = 3;
  writeln(I);
end.
