program test_const_bitwise_shift;

{ Constant-expression folding of the bitwise / shift operators. `shl` (a keyword
  token), `shr` (lexed as an identifier), `mod`, `and`, `or` -- previously only
  + - * div were accepted in a const expression, so `const X = 1 shl 16;` was a
  parse error ("Expected: begin, but got: shl"). Mind the flat right-grouping of
  ConstEval: parenthesise where evaluation order matters. }

const
  SHL16  = 1 shl 16;          { 65536 }
  SHR3   = 1024 shr 3;        { 128 }
  MOD5   = 17 mod 5;          { 2 }
  AND_   = 12 and 10;         { 8 }
  OR_    = 12 or 3;           { 15 }
  MASK   = (1 shl 8) or 255;  { 511 }
  TTSIZE = 1 shl 16;          { the examples/chess case }

begin
  writeln(SHL16);
  writeln(SHR3);
  writeln(MOD5);
  writeln(AND_);
  writeln(OR_);
  writeln(MASK);
  writeln(TTSIZE);
end.
