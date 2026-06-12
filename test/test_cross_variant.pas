program test_cross_variant;

{ Cross-target Variant oracle: same output on every target as on x86-64.
  Globals only — variant locals are not yet supported on cross targets. }

var
  v, w, r: Variant;
begin
  { scalar boxing + write dispatch }
  v := 42;
  writeln(v);
  v := 3.5;
  writeln(v);
  v := 'x';
  writeln(v);
  v := 'hello';
  writeln(v);

  { integer variant arithmetic }
  v := 10;
  w := 4;
  r := v + w;
  writeln(r);
  r := v - w;
  writeln(r);
  r := v * w;
  writeln(r);
  r := v / w;
  writeln(r);

  { comparisons }
  writeln(v > w);
  writeln(v < w);
  writeln(v = w);
  writeln(v <> w);

  { mixed double/int }
  v := 2.5;
  r := v * w;
  writeln(r);
  r := v + 1;
  writeln(r);

  { strings }
  v := 'ab';
  w := 'cd';
  r := v + w;
  writeln(r);
  writeln(v = w);
  writeln(v <> w);

  { variant := variant copy }
  v := w;
  writeln(v);
end.
