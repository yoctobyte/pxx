{ Real-valued constant EXPRESSIONS (bug-p-const-expressions-are-integer-only).
  The const evaluator was integer-only, which produced four different wrongs:
  an alias of a real const printed its IEEE bits as an integer, `: double = 3`
  stored 0.0, `: double = -3` stored Nan, and any real arithmetic was a parse
  error. Every value below is what `fpc -O- -Mobjfpc` prints. }
program test_const_real_expressions;
const
  Lit      = 3.14;
  Alias    = Lit;                  { alias of a real const }
  Scaled   = Lit * 2;              { real * integer }
  Sum      = 3.5 * 2.0 - 1.0;      { full additive/multiplicative chain }
  Parens   = (1.5 + 2.5) * 2;
  NegExpr  = -3.14 * 2;
  IntDiv   = 6 / 3;                { `/` is real division even on integers }
  Tiny     = 1e-9;
  N        = 10;                   { plain integer const, unchanged }
  Mixed    = N / 4;
  IntExpr  = 2 * 3 + 1;            { the integer path must not move }
  Shifted  = 1 shl 40;
  Sized    = SizeOf(Integer) * 2;
  TypedI: double = 3;              { integer literal into a real destination }
  TypedN: double = -3;
  TypedS: double = SizeOf(Integer);
  Arr: array[0..2] of double = (1.5, 2.5 * 2, Lit + 0.86);
var i: integer;
begin
  writeln(Lit:0:4, ' ', Alias:0:4, ' ', Scaled:0:4);
  writeln(Sum:0:2, ' ', Parens:0:2, ' ', NegExpr:0:4);
  writeln(IntDiv:0:2, ' ', Tiny:0:12, ' ', Mixed:0:4);
  writeln(IntExpr, ' ', Shifted, ' ', Sized);
  writeln(TypedI:0:2, ' ', TypedN:0:2, ' ', TypedS:0:2);
  for i := 0 to 2 do write(Arr[i]:0:2, ' ');
  writeln;
end.
