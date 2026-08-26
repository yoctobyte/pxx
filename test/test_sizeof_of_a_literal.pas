{ SizeOf of a BARE literal.

  fpc types a literal by its VALUE, not by whatever the expression parser would
  infer, so the width has nothing to do with `Integer`. Every number below is
  measured against fpc 3.2.2 (-Mobjfpc -O1); this file IS the spec for
  SizeOfLiteralToken in pasparser_name.inc.

  The traps: 128 and 255 are ONE byte (they fit Byte) while -129 is two (it
  needs SmallInt); a real literal is Single-typed here (4) even though it
  promotes to Double in arithmetic; and a string literal is its own
  array[1..N] of Char, so the answer is the LENGTH, not a handle's width. }
program test_sizeof_of_a_literal;
begin
  { unsigned reach: the smallest type that holds it, signed or not }
  WriteLn(SizeOf(1), ' ', SizeOf(127), ' ', SizeOf(128), ' ', SizeOf(255));
  WriteLn(SizeOf(256), ' ', SizeOf(32767), ' ', SizeOf(32768), ' ', SizeOf(65535));
  WriteLn(SizeOf(65536), ' ', SizeOf(100000), ' ', SizeOf(5000000000));
  { a leading minus is its own token and it changes the answer }
  WriteLn(SizeOf(-1), ' ', SizeOf(-129), ' ', SizeOf(-32769));
  { real, nil, Boolean }
  WriteLn(SizeOf(3.5), ' ', SizeOf(nil), ' ', SizeOf(True), ' ', SizeOf(False));
  { a string literal is an array of Char; the empty one still costs a byte }
  WriteLn(SizeOf('a'), ' ', SizeOf(''), ' ', SizeOf('abc'), ' ', SizeOf('hello world'));
end.
