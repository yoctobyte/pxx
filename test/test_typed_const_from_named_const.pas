{ A typed constant's string initialiser may NAME an untyped string constant, not
  only spell a literal.

  Four sites asked `CurTok.Kind <> tkString` and errored otherwise, so
  `const s1 = 'S1'; A: array[0..0] of ShortString = (s1);` was refused with
  `array constant: expected a string or char literal` while naming a constant
  whose literal text the compiler was already holding.

  THE CONTROL THAT IDENTIFIED THE CAUSE, and the reason this is a defect and not
  a missing feature: the INTEGER row below. `const n1 = 7; A: array[0..0] of
  Integer = (n1)` compiled throughout. Named constants are folded in
  initialisers; only the STRING path never looked. Four copies of a token test
  standing in for a question about the program.

  The substitution is exact rather than a conversion: an untyped string const is
  STORED as its literal's (SOffset, SLen) span into TokChars, which is the very
  pair each of these sites already captured from the token.

  NEGATIVE CONTROLS ARE ROWS HERE, NOT COMMENTS — an initialiser that accepts a
  named string const must still REFUSE a name that is not one, or the fix has
  replaced a wrong error with no error. `nosuch` (undeclared) and `n1` (declared,
  an Integer) are both still refused; those two are the rows that can fail if
  the guard is loosened to "any identifier". They are asserted in the Makefile
  recipe as `!` steps rather than here, since a refusal has no output to diff.

  Every row below is byte-identical to fpc 3.2.2. }
program test_typed_const_from_named_const;
const
  s1 = 'S1';
  s2 = 'cd';
  n1 = 7;
  ArrFromNamed: array[0..1] of ShortString = (s1, 'lit');
  ArrFromLit: array[0..0] of ShortString = ('S1');
  ArrInt: array[0..0] of Integer = (n1);          { the control — always worked }
  ScalarNamed: ShortString = s1;
  ScalarLit: ShortString = 'S1';
  CatNamedLit: ShortString = s1 + 'cd';
  CatLitNamed: ShortString = 'ab' + s2;
  CatNamedNamed: ShortString = s1 + s2;
  CatLitLit: ShortString = 'ab' + 'cd';
var
  VarArrFromNamed: array[0..0] of ShortString = (s1);
begin
  WriteLn('arr named  : ', ArrFromNamed[0], ' ', ArrFromNamed[1]);
  WriteLn('arr literal: ', ArrFromLit[0]);
  WriteLn('arr integer: ', ArrInt[0]);
  WriteLn('scalar     : ', ScalarNamed, ' ', ScalarLit);
  WriteLn('cat n+l    : ', CatNamedLit);
  WriteLn('cat l+n    : ', CatLitNamed);
  WriteLn('cat n+n    : ', CatNamedNamed);
  WriteLn('cat l+l    : ', CatLitLit);
  WriteLn('var array  : ', VarArrFromNamed[0]);
end.
