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

var a, b, c: AnsiString; i: Integer;
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
end.
