program test_op_record_result;
{ Operator overloads that RETURN a record. Regression for the bug where a
  record-valued operator result was miscompiled: into an explicit var it
  segfaulted, into an inferred (auto-typed) var it dropped the 2nd field.
  Covers explicit/inferred targets and local/global scope. 8-byte records
  only; by-value record params >8 bytes and operator results reused directly
  as operands are separate, pre-existing limitations. }
type
  TVec = record X, Y: Integer; end;

operator + (a, b: TVec): TVec;
begin Result.X := a.X + b.X; Result.Y := a.Y + b.Y; end;

procedure RunLocal;
var a, b, c: TVec;
begin
  a.X := 1; a.Y := 2; b.X := 3; b.Y := 4;
  c := a + b;                 { -> explicit local }
  writeln(c.X, ' ', c.Y);
  var d := a + b;             { -> inferred local }
  writeln(d.X, ' ', d.Y);
end;

var
  g, h, a, b: TVec;
begin
  RunLocal;
  a.X := 1; a.Y := 2; b.X := 3; b.Y := 4;
  g := a + b;                 { -> explicit global }
  writeln(g.X, ' ', g.Y);
  var hh := a + b;            { -> inferred global }
  writeln(hh.X, ' ', hh.Y);
  h := hh;
  writeln(h.X, ' ', h.Y);
end.
