program test_assign_types;
{ B0 regression: direct assignment now types the RHS correctly, so the old
  "assign via a temporary local" workarounds are unnecessary. Each case below
  used to be suspect; all must compile and produce the expected value directly. }
type
  PBuf = ^Byte;
  TRec = record
    s: string;
    buf: PBuf;
  end;

function Greet(n: string): string;
begin
  Greet := 'Hi ' + n;
end;

function Made: string;
begin
  Made := 'hello';
end;

var
  a, b, s: string;
  c: Char;
  ok: Boolean;
  x: Integer;
  r: TRec;
begin
  { string concat straight into the target }
  a := 'foo'; b := 'bar';
  s := a + b + 'baz';
  writeln(s);                 { foobarbaz }

  { function result inside a concat assignment }
  s := Greet('world') + '!';
  writeln(s);                 { Hi world! }

  { single-char literal -> string }
  s := 'x';
  writeln(s);                 { x }

  { char -> string record field }
  c := 'Q';
  r.s := c;
  writeln(r.s);               { Q }

  { function-returning-string -> record field directly }
  r.s := Made;
  writeln(r.s);               { hello }

  { boolean expression -> bool var }
  x := 5;
  ok := x > 3;
  if ok then writeln('Y') else writeln('N');   { Y }

  { pointer record-field indexed directly (read + write) }
  r.buf := GetMem(4);
  r.buf[0] := 65;
  writeln(r.buf[0]);          { 65 }
end.
