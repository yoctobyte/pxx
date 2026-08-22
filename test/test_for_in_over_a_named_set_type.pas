program test_for_in_over_a_named_set_type;
type TE = (ra, rb, rc);
     TS = set of Char;
     TB = set of 0..7;
     TES = set of TE;
     TBy = set of Byte;
var cs: TS; b: TB; es: TES; by: TBy; c: Char; n: Integer; e: TE;
begin
  cs := ['a','c','e'];
  for c in cs do Write(c);
  WriteLn;
  b := [1,3,6];
  for n in b do Write(n);
  WriteLn;
  es := [ra, rc];
  for e in es do Write(Ord(e));
  WriteLn;
  by := [9, 200];
  for n in by do Write(n, ' ');
  WriteLn;
  { Continue inside each }
  for c in cs do begin if c = 'c' then Continue; Write(c); end;
  WriteLn;
  for n in b do begin if n = 3 then Continue; Write(n); end;
  WriteLn;
end.
