program test_cross_aggregate_stackargs;
{ A function returning a record by value (hidden-destination/sret ABI) AND taking
  more argument words than fit in registers — the case that hit
  `target arm32: aggregate result with more than 4 param words not supported`
  (feature-arm32-large-aggregate-result). Exercises the stack-argument + hidden
  -dest interaction. Output must match x86-64 on every target. }

type R = record a, b, c: Double end;

{ 5 scalar word args + aggregate result (j = 5 > 4 on arm32) }
function Make5(p, q, s, t, u: Integer): R;
begin
  Make5.a := p + q;
  Make5.b := s + t;
  Make5.c := u;
end;

{ 7 scalar word args }
function Make7(p, q, s, t, u, v, w: Integer): R;
begin
  Make7.a := p + q + s;
  Make7.b := t + u;
  Make7.c := v + w;
end;

{ mixed widths: Int64 (2 words each) + scalar => 2+2+1 = 5 words }
function MakeMix(x: Int64; y: Int64; z: Integer): R;
begin
  MakeMix.a := x + y;
  MakeMix.b := z;
  MakeMix.c := x - y;
end;

{ record-by-ref arg + 4 scalars => 1 + 4 = 5 words }
function MakeRec(const base: R; p, q, s, t: Integer): R;
begin
  MakeRec.a := base.a + p;
  MakeRec.b := base.b + q;
  MakeRec.c := s + t;
end;

var r: R; b: R;
begin
  r := Make5(1, 2, 3, 4, 5);
  writeln(r.a:0:0, ' ', r.b:0:0, ' ', r.c:0:0);     { 3 7 5 }

  r := Make7(1, 2, 3, 4, 5, 6, 7);
  writeln(r.a:0:0, ' ', r.b:0:0, ' ', r.c:0:0);     { 6 9 13 }

  r := MakeMix(100, 200, 7);
  writeln(r.a:0:0, ' ', r.b:0:0, ' ', r.c:0:0);     { 300 7 -100 }

  b.a := 10; b.b := 20; b.c := 30;
  r := MakeRec(b, 1, 2, 3, 4);
  writeln(r.a:0:0, ' ', r.b:0:0, ' ', r.c:0:0);     { 11 22 7 }
end.
