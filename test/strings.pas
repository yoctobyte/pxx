program Strings;
var
  s, t: string;
  n: Integer;

begin
  s := 'Hello, World!';
  writeln(s);

  t := 'Pascal26';
  writeln(t);

  n := Length(s);
  writeln(n);

  s := t;
  writeln(s);

  writeln(Length(t));
end.
