program TestCastString;
var
  s, t: String;
  c: Char;
  i: Integer;
begin
  c := 'Q';
  s := String(c);
  writeln('[', s, ']');             { [Q] }
  writeln(String(Char(65)));        { A }
  if String(c) = 'Q' then writeln('eq');

  s := 'hello';
  t := String(s);                   { identity }
  writeln(t);                       { hello }
  writeln(String(s));               { hello }

  for i := 88 to 90 do
  begin
    s := String(Char(i));
    write(s);
  end;
  writeln;                          { XYZ }
end.
