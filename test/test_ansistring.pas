{$define PXX_MANAGED_STRING}
program test_ansistring;

var
  s: AnsiString;
  t: AnsiString;
  c: Char;

procedure TestLocal;
var
  u: AnsiString;
begin
  u := 'LocalString';
  writeln(u);
  writeln(Length(u));
  if u = 'LocalString' then
    writeln('Local equal ok')
  else
    writeln('Local equal fail');
end;

begin
  { Initially nil/empty }
  writeln(Length(s));
  if s = '' then
    writeln('Initially empty ok')
  else
    writeln('Initially empty fail');

  s := 'Hello';
  writeln(s);
  writeln(Length(s));

  t := s;
  writeln(t);
  if t = s then
    writeln('Assignment equal ok')
  else
    writeln('Assignment equal fail');

  { Modify first character }
  s[1] := 'h';
  writeln(s);
  writeln(t); { Should print Hello (isolated via COW) }
  if (s = 'hello') and (t = 'Hello') then
    writeln('COW index write ok')
  else
    writeln('COW index write fail');

  TestLocal;

  { Assign char variable to AnsiString }
  c := 'X';
  s := c;
  writeln(s);
  if s = 'X' then
    writeln('Char assign ok')
  else
    writeln('Char assign fail');

  s := 'Hello';
  t := ' World';
  s := s + t + '!';
  writeln(s);

  t := s;
  SetLength(s, 5);
  writeln(s);
  writeln(t);

  s := '';
  writeln(Length(s));
  if s = '' then
    writeln('Clear empty ok')
  else
    writeln('Clear empty fail');
end.
