{$mode objfpc}
program test_copy_delete_insert_are_one_move;
{ The builtin Copy/Delete/Insert (no sysutils) build their result with one
  SetLength + Move. Every clamp edge, a frozen short result, and a long string
  whose bytes must all arrive. }
var
  s, t, big: AnsiString;
  sh: string[5];
  i, sum: Integer;
begin
  s := 'Hello, world';
  WriteLn('[', Copy(s, 1, 5), ']');
  WriteLn('[', Copy(s, 8, 100), ']');
  WriteLn('[', Copy(s, 8, MaxInt), ']');
  WriteLn('[', Copy(s, 0, 3), ']');
  WriteLn('[', Copy(s, -5, 3), ']');
  WriteLn('[', Copy(s, 13, 2), ']');
  WriteLn('[', Copy(s, 12, 2), ']');
  WriteLn('[', Copy(s, 3, 0), ']');
  WriteLn('[', Copy(s, 3, -1), ']');
  WriteLn('[', Copy('', 1, 3), ']');
  WriteLn(Copy(s, 8, 5)[2]);
  sh := Copy(s, 1, 12);
  WriteLn('[', sh, '] ', Length(sh));

  t := s; Delete(t, 1, 7);   WriteLn('[', t, ']');
  t := s; Delete(t, 6, 100); WriteLn('[', t, ']');
  t := s; Delete(t, 6, 1);   WriteLn('[', t, ']');
  t := s; Delete(t, 12, 1);  WriteLn('[', t, ']');
  t := s; Delete(t, 13, 1);  WriteLn('[', t, ']');
  t := s; Delete(t, 0, 3);   WriteLn('[', t, ']');
  t := s; Delete(t, 3, 0);   WriteLn('[', t, ']');
  t := s; Delete(t, 1, MaxInt); WriteLn('[', t, ']');

  t := s; Insert('XY', t, 1);   WriteLn('[', t, ']');
  t := s; Insert('XY', t, 6);   WriteLn('[', t, ']');
  t := s; Insert('XY', t, 13);  WriteLn('[', t, ']');
  t := s; Insert('XY', t, 99);  WriteLn('[', t, ']');
  t := s; Insert('XY', t, -4);  WriteLn('[', t, ']');
  t := s; Insert('', t, 3);     WriteLn('[', t, ']');
  t := '';  Insert('abc', t, 1); WriteLn('[', t, ']');

  { a shared source is left alone }
  t := s; Insert('!', t, 1); Delete(t, 2, 1);
  WriteLn('[', s, '] [', t, ']');

  SetLength(big, 5000);
  for i := 1 to 5000 do big[i] := Chr(32 + i mod 90);
  t := Copy(big, 3, 4990);
  sum := 0;
  for i := 1 to Length(t) do sum := sum + Ord(t[i]) * (i mod 7 + 1);
  WriteLn(Length(t), ' ', sum, ' ', t = Copy(big, 3, 4990), ' ', t[1], t[4990]);
  Delete(big, 10, 4000); Insert(Copy(t, 1, 3), big, 5);
  WriteLn(Length(big), ' ', Copy(big, 1, 12));
end.
