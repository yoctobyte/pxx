program test_own_lang_first_c_first;
{ The same rule with BOTH variables flipped: the C file is named FIRST in the
  uses clause and carries NO alias.

  This is the row that distinguishes own-language-first from the fix to
  bug-c-definition-of-an-intrinsic-name-overwrites-the-pascal-routine. That bug
  made the C body seize the Pascal proc entry; a resolver that merely stopped
  the seizure could still let import ORDER decide, and would pass the other
  test while failing this one. Precedence must not be a tie-break.
  feature-a-own-language-first-symbol-resolution }
uses './olf_cmath.c', math;
begin
  WriteLn('Exp=', Exp(1.0):0:4);
  WriteLn('Sqrt=', Sqrt(16.0):0:4);
end.
