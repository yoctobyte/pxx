program test_byval_record_temp;
{ Regression: a function-result TEMPORARY passed to a plain (non-const) by-value
  record param (>8 bytes, passed by-ref for ABI) is accepted and copied — the
  callee makes its own copy, so a temp is sound. var/out still need an lvalue.
  (bug-plain-byvalue-record-param-temp.) Uses Int64 fields so the value path is
  exercised independently of the separate float-record-return bug. }
type Ri = record a, b, c: Int64 end;
function Mk(x, y, z: Int64): Ri;
begin Mk.a := x; Mk.b := y; Mk.c := z; end;
function Add(p, q: Ri): Ri;                 { plain by-value record params }
begin Add.a := p.a + q.a; Add.b := p.b + q.b; Add.c := p.c + q.c; end;
function Scale(p: Ri; s: Int64): Ri;        { plain by-value + scalar }
begin Scale.a := p.a * s; Scale.b := p.b * s; Scale.c := p.c * s; end;
var r: Ri;
begin
  r := Add(Mk(1, 2, 3), Mk(10, 20, 30));    { nested temps -> was a parse error }
  writeln(r.a, ' ', r.b, ' ', r.c);          { 11 22 33 }
  r := Scale(Add(Mk(1, 1, 1), Mk(2, 2, 2)), 5);   { temp + named mix }
  writeln(r.a, ' ', r.b, ' ', r.c);          { 15 15 15 }
  r := Mk(7, 8, 9);
  r := Add(r, Mk(1, 1, 1));                  { named + temp }
  writeln(r.a, ' ', r.b, ' ', r.c);          { 8 9 10 }
end.
