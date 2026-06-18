program TestCastCharBool;
var
  i: Integer;
  c: Char;
  b: Boolean;
begin
  i := 65;
  c := Char(i);
  writeln(c);                          { A }
  if Char(66) = 'B' then writeln('charcmp');
  writeln(Ord(Char(67)));              { 67 }

  b := Boolean(1);
  if b then writeln('btrue');
  b := Boolean(0);
  if not b then writeln('bfalse');

  { cast inside an expression }
  for i := 72 to 74 do write(Char(i));
  writeln;
end.
