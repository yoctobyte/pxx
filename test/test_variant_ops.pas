program test_variant_ops;
{ Variant arithmetic + comparison: closed double-dispatch. int+int stays int,
  any double promotes to double; comparisons yield Boolean (0/1 here). }
var
  a, b, r: Variant;
begin
  a := 5;
  b := 3;
  r := a + b;        writeln(r);   { 8   (int+int -> int) }
  r := a - b;        writeln(r);   { 2 }
  r := a * b;        writeln(r);   { 15 }

  a := 5;
  b := 2.5;
  r := a + b;        writeln(r);   { 7.5 (int+double -> double) }
  r := a * b;        writeln(r);   { 12.5 }

  a := 5;
  b := 3;
  writeln(a > b);    { 1 }
  writeln(a < b);    { 0 }
  writeln(a = b);    { 0 }

  a := 2.5;
  b := 2.5;
  writeln(a = b);    { 1 }
  writeln(a >= b);   { 1 }

  { Variant op scalar literal (scalar gets boxed into a temp) }
  a := 10;
  r := a + 1;        writeln(r);   { 11 }
  writeln(a < 20);   { 1 }
end.
