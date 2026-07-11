program test_str_variable_width;
{ Str / write / writeln with VARIABLE width/precision expressions (FPC-legal):
  Str(x:len:dec, s), writeln(x:w:d) — previously only literals were accepted
  ("error: Str: expected integer width after :"). Literal forms must keep
  byte-identical behavior; variable forms must match the literal ones. }
var
  i, w, d: Integer;
  r: Double;
  s1, s2: string;
begin
  i := 42;
  w := 6;

  { Str integer: literal vs variable width must agree }
  Str(i:6, s1);
  Str(i:w, s2);
  writeln('[', s1, ']');
  if s1 = s2 then writeln('int-eq') else writeln('int-NE ', s1, '/', s2);

  { width as full expression }
  Str(i:w+2, s2);
  writeln('[', s2, ']');

  { Str float: literal vs variable width/decimals }
  r := 3.14159;
  d := 3;
  w := 9;
  Str(r:9:3, s1);
  Str(r:w:d, s2);
  writeln('[', s1, ']');
  if s1 = s2 then writeln('float-eq') else writeln('float-NE ', s1, '/', s2);

  { console write with variable width/decimals }
  writeln(i:w);
  writeln(r:w:d);
  { literal path unchanged }
  writeln(i:9);
  writeln(r:9:3);
end.
