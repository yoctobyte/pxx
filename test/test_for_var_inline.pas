program test_for_var_inline;
{ Delphi 10.3 Rio inline loop variable: `for var i := a to b` declares a fresh
  Integer counter (no separate `var i:`); `for var x in c` declares a fresh
  loop var whose type is inferred from the iterable's element type -- both
  done, feature-inline-loop-var-rio. }
type
  TRec = record a, b: Integer; end;
  TSE = (sA, sB, sC);
var
  t, s: Integer;
  arr: array[0..3] of Integer;
  recs: array[0..1] of TRec;
  msg: string;
  ss: set of TSE;
  i: Integer;
begin
  t := 0;
  for var i := 0 to 4 do t := t + i;          { 0+1+2+3+4 }
  writeln(t);                                  { 10 }

  s := 0;
  for var i := 3 downto 1 do
    for var j := 1 to i do s := s + 1;          { 3+2+1 }
  writeln(s);                                  { 6 }

  { for-in inline: array of Integer }
  for i := 0 to 3 do arr[i] := i * 10;
  for var x in arr do writeln('x=', x);

  { for-in inline: string (element = Char) }
  msg := 'abc';
  for var c in msg do writeln('c=', c);

  { for-in inline: array of record }
  recs[0].a := 1; recs[0].b := 2;
  recs[1].a := 3; recs[1].b := 4;
  for var r in recs do writeln('r=', r.a, ',', r.b);

  { for-in inline: set membership scan }
  ss := [sA, sC];
  for var m in ss do writeln('m=', ord(m));
end.
