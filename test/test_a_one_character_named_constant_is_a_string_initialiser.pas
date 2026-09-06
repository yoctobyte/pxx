program test_a_one_character_named_constant_is_a_string_initialiser;
{ `const c1 = 'A'; A: array[0..1] of ShortString = (c1, c2)` was refused with
  `expected a string or char literal` while naming a constant whose character
  the compiler was already holding.

  TWO CORRECT DECISIONS, EACH RIGHT ALONE, that between them refused a program.
  ParseConstSection routes a ONE-CHARACTER literal to AddConst(..., tyChar, ...)
  on purpose, so that `Ord(c1)` is the character's ordinal and not a string's
  address; multi-character literals go to the StrConst span table. The string
  initialiser helpers looked only in the span table. So the LENGTH of the
  literal picked the storage class, and only one storage class was reachable
  from an initialiser.

  Row 9 is the control that separates the two: the same declaration with
  two-character values always compiled, so length was the only variable.
  Row 10 is the decision that must SURVIVE the fix -- Ord of a one-char const
  is still its ordinal, which is the whole reason the char routing exists.
  Rows 7-8 are the concatenation arm, a documented double case: fixing only the
  single-operand side would leave `c1 + 'b'` refused while `c1` compiled.
  Rows 11-13 are what a deleted PRE-GUARD must not have broken -- it restated
  the helpers' acceptance test two lines earlier and had drifted narrower than
  them, so it refused the char const before the helper ever ran.
  tstring3.pp's char half is this; its resourcestring half is a separate gap. }
{$mode objfpc}
const
  c1 = 'A'; c2 = 'B';
  s1 = 'String1';
  A: array[0..1] of shortstring = (c1, c2);
  B: array[0..1] of ansistring  = (c1, c2);
  C: array[0..1] of shortstring = (c1, s1);
  D: shortstring = c1;
  E: ansistring  = c1;
  G: shortstring = c1 + 'b';
  H: shortstring = s1 + c1;
  M: array[0..1] of shortstring = (s1, 'lit');
  F = 'a' < 'b';
  K: Char = 'z';
  n1 = 7;
  N: array[0..1] of Integer = (n1, 8);
var i: LongInt;
begin
  for i := 0 to 1 do WriteLn('1.', i, ' ', A[i]);
  for i := 0 to 1 do WriteLn('2.', i, ' ', B[i]);
  for i := 0 to 1 do WriteLn('3.', i, ' ', C[i]);
  WriteLn('4 ', D, ' ', Length(D));
  WriteLn('5 ', E, ' ', Length(E));
  WriteLn('7 ', G);
  WriteLn('8 ', H);
  for i := 0 to 1 do WriteLn('9.', i, ' ', M[i]);
  WriteLn('10 ', Ord(c1), ' ', Ord(c2));
  WriteLn('11 ', F);
  WriteLn('12 ', K, ' ', Ord(K));
  WriteLn('13 ', N[0], ' ', N[1]);
end.
