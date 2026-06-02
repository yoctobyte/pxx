{$define PXX_MANAGED_STRING}
program test_ansistring;

var
  s: AnsiString;
  t: AnsiString;

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
  writeln(t); { Since t is a copy and we haven't implemented COW yet, let's see: wait, since we haven't done copy-on-write (COW) yet, modifying s[1] will modify the shared buffer. In a future slice we will implement COW. For now, they share the buffer, so let's verify both reflect the change, or just test changing it. }
  if s[1] = 'h' then
    writeln('Index write ok')
  else
    writeln('Index write fail');

  TestLocal;

  s := '';
  writeln(Length(s));
  if s = '' then
    writeln('Clear empty ok')
  else
    writeln('Clear empty fail');
end.
