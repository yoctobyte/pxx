program test_const_set;

{ Named set constants: untyped `const S = [..]`, typed `const S: TS = [..]`,
  ranges, and use in `in` / set arithmetic. The 32-byte mask is baked into rodata
  at decl time; a use yields its address like a literal set. }

type
  TColor = (red, green, blue);
  TCS = set of TColor;

const
  Digits = [1, 3, 5, 7, 9];
  Lo: TCS = [red, blue];
  Range  = [10..12, 20];

var i, cnt: integer;
begin
  cnt := 0;
  for i := 0 to 9 do if i in Digits then Inc(cnt);
  writeln('digits=', cnt);                 { 5 }

  if green in Lo then writeln('green=in') else writeln('green=out');  { out }
  if blue  in Lo then writeln('blue=in')  else writeln('blue=out');   { in }

  cnt := 0;
  for i := 0 to 30 do if i in Range then Inc(cnt);
  writeln('range=', cnt);                  { 4 (10,11,12,20) }

  if 3 in (Digits + [2]) then writeln('union=ok');
  if (5 in (Digits * [5, 6])) and not (2 in (Digits * [5, 6])) then
    writeln('inter=ok');
end.
