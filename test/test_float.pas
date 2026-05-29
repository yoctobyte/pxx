program test_float;

var
  s: Single;
  d: Double;
  r: Real;
  e: Extended;

procedure Check(ok: Boolean);
begin
  if ok then
    writeln(1)
  else
    writeln(0);
end;

begin
  s := 1.5;
  s := s + 2.25;
  Check(s > 3.7);
  Check(s < 3.8);

  d := (6.0 + 2.0) * (5.0 - 1.5) / 7.0;
  Check(d > 3.9);
  Check(d < 4.1);
  Check(d > 3.5);
  Check(d <= 4.0);

  r := 2 + 3.5;
  Check(r > 5.4);
  Check(r < 5.6);
  r := 7.5 - 2;
  Check(r = 5.5);
  r := 3 * 2.5;
  Check(r = 7.5);
  r := 7 / 2;
  Check(r > 3.4);
  Check(r < 3.6);

  d := 1.25e1;
  Check(d = 12.5);
  d := -1.5;
  Check(d < 0.0);
  Check(d = -1.5);

  e := 10.0;
  e := e / 4.0;
  Check(e = 2.5);
end.
