program test_cross_string;
{ Managed AnsiString on cross targets (compile with -dPXX_MANAGED_STRING).
  Exercises literal assignment, concatenation, var-to-var retain with
  copy-on-write independence, string parameters and results, and equality.
  i386 string IR ops call the builtinheap Pascal helpers directly (no x86-64
  shim layer). Output is identical on every target (oracle pattern). }

function Greet(name: AnsiString): AnsiString;
begin
  Greet := 'Hi, ' + name;
end;

procedure AppendSuffix(var s: AnsiString);
begin
  s := s + ' suffix';
end;

procedure TestLocalLeak;
var localStr: AnsiString;
begin
  localStr := 'local';
  localStr := localStr + ' temp';
end;

var a, b, c: AnsiString; i: Integer; ch: Char;
begin
  a := 'foo';
  b := 'bar';
  c := a + b;
  writeln(c);            { foobar }

  c := a;                { var-to-var: retain }
  a := 'changed';
  writeln(c);            { foo  — c independent of a }

  writeln(Greet(b));     { Hi, bar  — param + result }

  if c = 'foo' then writeln('eq') else writeln('ne');   { eq }
  if c = b then writeln('eq') else writeln('ne');       { ne }

  for i := 1 to 3 do
    writeln(Greet(c));   { Hi, foo  x3 }

  { Test by-ref string params }
  c := 'start';
  AppendSuffix(c);
  writeln(c);            { start suffix }

  { Test inline tyString concat }
  writeln('hello' + ' ' + 'world'); { hello world }

  { Test char-combo comparisons }
  c := 'x';
  ch := 'x';
  if c = 'x' then writeln('c = x') else writeln('c <> x');
  if 'x' = c then writeln('x = c') else writeln('x <> c');
  if c = ch then writeln('c = ch') else writeln('c <> ch');
  if ch = c then writeln('ch = c') else writeln('ch <> c');

  c := 'xyz';
  if c = 'x' then writeln('xyz = x') else writeln('xyz <> x');
  if 'x' = c then writeln('x = xyz') else writeln('x <> xyz');
  if c = ch then writeln('xyz = ch') else writeln('xyz <> ch');
  if ch = c then writeln('ch = xyz') else writeln('ch <> xyz');

  { Test scope-exit release }
  for i := 1 to 10 do
    TestLocalLeak;
  writeln('leak test done');
end.
