program test_unary_minus_on_a_record_with_an_operator;
{ The refusal for a record with NO unary minus must leave every declared one
  working: a global `operator -`, an advanced record's `class operator -`, and
  ucomplex's (added here, as fpc's ucomplex declares it). Expected output is
  fpc 3.2.2's.
  bug-a-unary-minus-on-a-record-without-an-operator-compiles-and-segfaults }
{$mode objfpc}{$modeswitch advancedrecords}
uses ucomplex;
type
  R = record x, y: Double; end;
  V = record
    x: Integer;
    class operator -(const a: V): V;
  end;
operator -(const a: R): R;
begin
  Result.x := -a.x; Result.y := -a.y;
end;
operator =(const a, b: R): Boolean;
begin
  Result := (a.x = b.x) and (a.y = b.y);
end;
class operator V.-(const a: V): V;
begin
  Result.x := -a.x;
end;
var a, b: R; va, vb: V; z, w: Complex;
begin
  a.x := 1; a.y := 2;
  b := -a;
  writeln(b.x:0:1, ' ', b.y:0:1);
  writeln(a <> -a, ' ', a = -(-a));
  va.x := 5; vb := -va; writeln(vb.x);
  z := cinit(1, 2); w := -z; writeln(w.re:0:1, ' ', w.im:0:1);
  writeln(z <> -z, ' ', z = -(-z));
end.
