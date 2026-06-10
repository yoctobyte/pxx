program write_test;

var
  c: Char;
  b: Boolean;
  i: Integer;

begin
  { characters }
  c := 'Z';
  write(c);
  write(c);
  writeln;

  { booleans }
  b := true;
  write(b);
  write(false);
  writeln;

  { integers with width }
  i := 42;
  writeln(i:6);
  writeln(-7:6);
  writeln(1000:4);
  writeln(0:3);

  { const strings with width }
  writeln('ab':5);
  writeln('hello':8);
end.
