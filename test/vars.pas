program Vars;
var
  x, y, z: Integer;
  i: Integer;
begin
  x := 10;
  y := 32;
  z := x + y;
  writeln('Sum: ', z);

  writeln('Countdown:');
  for i := 5 downto 1 do
    writeln(i);

  writeln('Squares:');
  for i := 1 to 5 do
  begin
    writeln(i * i);
  end;

  if z > 40 then
    writeln('big')
  else
    writeln('small');

  i := 0;
  while i < 3 do
  begin
    writeln('loop ', i);
    inc(i);
  end;
end.
