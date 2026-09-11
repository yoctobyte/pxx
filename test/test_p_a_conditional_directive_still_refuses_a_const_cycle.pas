program test_p_a_conditional_directive_still_refuses_a_const_cycle;
{ `const A = B; B = A;` is legal to WRITE, and once a const may name another
  const the walk that resolves it can follow that pair forever. The guard is a
  hop cap, and this is its positive control.
  IT IS THE ONE DECLINE THAT MATTERS MOST, because its failure mode is not a
  wrong answer -- it is a HANG, which no output assertion anywhere can observe.
  The Makefile row asserts the compile FAILS and that the message names A. }
const A = B; B = A;
{$if A > 0}
{$endif}
begin WriteLn('this program must never be reached'); end.
