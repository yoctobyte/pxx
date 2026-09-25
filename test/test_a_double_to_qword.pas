{ A Double or Single assigned to a QWord from 2^63 up. The assignment rounds
  (ties to even, as for every integer destination) and used the SIGNED
  conversion, so all of these printed 9223372036854775807. fpc refuses the
  assignment outright; pxx accepts it, so the value it gives must be right.
  None of the expected values equals the saturation value. }
program test_a_double_to_qword;
var
  d: Double;
  s: Single;
  q: QWord;
  a: array[0..4] of Double;
  i: Integer;
begin
  a[0] := 1e19;
  a[1] := 9223372036854775808.0;
  a[2] := 1.8e19;
  a[3] := 3.5;
  a[4] := 2.5;
  for i := 0 to 4 do
  begin
    d := a[i];
    q := d;
    WriteLn(i, ' ', q);
  end;
  s := 1e19;
  q := s;
  WriteLn('single ', q);
end.
