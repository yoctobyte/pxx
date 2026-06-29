{ Regression: integer typecasts + 64-bit folding in const initializers.
  feature-const-eval-typecast-int64. }
program test_const_typecast;
type
  TSocket = LongInt;
  TByteAlias = Byte;
  TWordAlias = Word;
const
  A = Int64(1) shl 52;            { 64-bit, no overflow }
  B = (Int64(1) shl 52) - 1;      { cast inside an outer paren }
  C = Integer(300);               { 32-bit pass-through }
  D = Byte(257);                  { wraps to 8-bit -> 1 }
  E = Word(-1);                   { unsigned 16-bit -> 65535 }
  F = ShortInt(200);             { signed 8-bit wrap -> -56 }
  G = Cardinal(-1);               { unsigned 32-bit -> 4294967295 }
  H = TSocket(NOT(0));            { named alias cast -> signed 32-bit -1 }
  I = TByteAlias(257);            { named alias cast -> 1 }
  J = TWordAlias(-1);             { named alias cast -> 65535 }
begin
  writeln(A);
  writeln(B);
  writeln(C);
  writeln(D);
  writeln(E);
  writeln(F);
  writeln(G);
  writeln(H);
  writeln(I);
  writeln(J);
end.
