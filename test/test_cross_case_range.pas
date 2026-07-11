program test_cross_case_range;
{ case-of with inclusive ranges (lo..hi), mixed with single/list labels and an
  else clause, over integer and char selectors. Byte-identical on every target. }
var i, c: Integer; s: AnsiString;
begin
  c := 0;
  for i := 0 to 20 do
    case i of
      0..5: c := c + 1;
      10, 12, 14: c := c + 10;
      15..18: c := c + 100;
    else c := c + 1000;
    end;
  writeln('ints=', c);
  c := 0;
  for i := Ord('a') to Ord('z') do
    case Chr(i) of
      'a'..'e', 'f': c := c + 1;
      'x'..'z': c := c + 100;
    end;
  writeln('chars=', c);
  s := '';
  for i := 0 to 9 do
    case i of
      0..2: s := s + 'L';
      3..6: s := s + 'M';
    else s := s + 'H';
    end;
  writeln('bucket=', s);
end.
