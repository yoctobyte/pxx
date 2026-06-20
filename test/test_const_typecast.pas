{ Regression: integer typecasts + 64-bit folding in const initializers.
  feature-const-eval-typecast-int64. }
program test_const_typecast;
const
  A = Int64(1) shl 52;            { 64-bit, no overflow }
  B = (Int64(1) shl 52) - 1;      { cast inside an outer paren }
  C = Integer(300);               { 32-bit pass-through }
  D = Byte(257);                  { wraps to 8-bit -> 1 }
  E = Word(-1);                   { unsigned 16-bit -> 65535 }
  F = ShortInt(200);             { signed 8-bit wrap -> -56 }
  G = Cardinal(-1);               { unsigned 32-bit -> 4294967295 }
begin
  writeln(A);
  writeln(B);
  writeln(C);
  writeln(D);
  writeln(E);
  writeln(F);
  writeln(G);
end.
