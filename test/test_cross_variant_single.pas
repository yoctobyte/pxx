program test_cross_variant_single;

{ Cross-target Variant single/extended oracle: a single boxed into a Variant
  widens to the double payload (VT_DOUBLE), so output matches x86-64 on every
  target. Globals only — variant locals are not yet supported on cross. }

var
  v, w, r: Variant;
  s: single;
  e: extended;
begin
  s := 3.5;
  v := s;
  writeln(v);

  s := 1.25;
  w := 2;
  r := v + w;          { 3.5 + 2 }
  writeln(r);
  r := w * s;          { 2 * 1.25 }
  writeln(r);

  e := 10.5;
  v := e;
  writeln(v);

  s := -0.5;
  v := s;
  writeln(v);
end.
