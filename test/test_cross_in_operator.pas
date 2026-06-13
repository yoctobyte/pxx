program test_cross_in_operator;

{ Cross-target `in` set-membership oracle. Set expressions mix single constant
  members and [lo..hi] ranges; the cross backends evaluate membership without a
  materialised set value. Output is identical on every target as on x86-64. }

var
  c: Char;
  i: Integer;
begin
  for i := 0 to 6 do
  begin
    c := Chr(94 + i * 5);
    if c in ['a'..'e', 'z', '0'..'9'] then
      writeln('Y ', c)
    else
      writeln('N ', c);
  end;

  if 3 in [1, 3, 5] then writeln('three-in') else writeln('three-out');
  if 4 in [1, 3, 5] then writeln('four-in') else writeln('four-out');

  for i := 0 to 12 do
    if i in [2..4, 8, 10..11] then
      writeln(i, ' member')
    else
      writeln(i, ' no');
end.
