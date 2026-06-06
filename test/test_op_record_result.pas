program test_op_record_result;
type
  TVec = record X, Y: Integer; end;
  TR3 = record A, B, C: Integer; end;

operator + (a, b: TVec): TVec;
begin Result.X := a.X + b.X; Result.Y := a.Y + b.Y; end;

operator + (const a, b: TR3): TR3;
begin
  Result.A := a.A + b.A;
  Result.B := a.B + b.B;
  Result.C := a.C + b.C;
end;

function Add3(a, b: TR3): TR3;
begin
  Result.A := a.A + b.A;
  Result.B := a.B + b.B;
  Result.C := a.C + b.C;
end;

procedure RunLocal;
var a, b, c: TVec;
begin
  a.X := 1; a.Y := 2; b.X := 3; b.Y := 4;
  c := a + b;                 { -> explicit local }
  writeln(c.X, ' ', c.Y);
  var d := a + b;             { -> inferred local }
  writeln(d.X, ' ', d.Y);

  { Chained operator test }
  var e := a + b + a;
  writeln(e.X, ' ', e.Y);
end;

var
  g, h, a, b: TVec;
  p, q: TR3;
begin
  RunLocal;
  a.X := 1; a.Y := 2; b.X := 3; b.Y := 4;
  g := a + b;                 { -> explicit global }
  writeln(g.X, ' ', g.Y);
  var hh := a + b;            { -> inferred global }
  writeln(hh.X, ' ', hh.Y);
  h := hh;
  writeln(h.X, ' ', h.Y);

  { Chained operator test (global) }
  var chainG := a + b + a;
  writeln(chainG.X, ' ', chainG.Y);

  { By-value record > 8 bytes test }
  p.A := 10; p.B := 20; p.C := 30;
  q.A := 100; q.B := 200; q.C := 300;
  var r1 := Add3(p, q);
  writeln(r1.A, ' ', r1.B, ' ', r1.C);

  { const record operator test }
  var r2 := p + q;
  writeln(r2.A, ' ', r2.B, ' ', r2.C);
end.
