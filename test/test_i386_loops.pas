program loops;

{ i386 slice 4: for/downto/repeat/Inc/Dec. Output must match x86-64. }
var i, s: Integer;
begin
  s := 0;
  for i := 1 to 5 do s := s + i;
  writeln(s);
  for i := 5 downto 1 do s := s - 1;
  writeln(s);
  i := 0;
  repeat
    Inc(i);
  until i >= 3;
  writeln(i);
  Dec(i, 2);
  writeln(i);
end.
