program TestForInNative;
type
  TWeekday = (Mon, Tue, Wed, Thu, Fri);
var
  sa: array[0..4] of Integer;
  da: array of Integer;
  s: AnsiString;
  i, sum: Integer;
  c: Char;
  d: TWeekday;
begin
  { static array }
  for i := 0 to 4 do sa[i] := (i + 1) * 10;
  sum := 0;
  for i in sa do sum := sum + i;
  writeln('static sum=', sum);

  { dynamic array }
  SetLength(da, 3);
  da[0] := 100; da[1] := 200; da[2] := 300;
  sum := 0;
  for i in da do sum := sum + i;
  writeln('dyn sum=', sum);

  { string char iteration }
  s := 'abc';
  for c in s do writeln('char=', c);

  { enum type iteration }
  for d in TWeekday do writeln('day=', Ord(d));
end.
