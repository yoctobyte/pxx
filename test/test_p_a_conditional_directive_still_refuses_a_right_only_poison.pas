program test_p_a_conditional_directive_still_refuses_a_right_only_poison;
{ THE POSITIVE CONTROL FOR THE SHORT-CIRCUIT FIX, AND IT MUST NOT COMPILE.
  `(X <> 3) and declared(X)` with X absent is False arithmetically -- and fpc
  3.2.2 REFUSES it, because fpc evaluates left to right and the comparison comes
  first. Answering it would accept a directive fpc rejects, and a conditional
  taking a branch fpc does not take produces a DIFFERENT PROGRAM.
  So the deferral is LEFT-ONLY, and this file is how that is checked rather than
  assumed: without a row like it, a later widening to "either operand may settle
  it" would look like an improvement and pass every other test in the tree.
  The Makefile row asserts the compile FAILS and that the message names NOPE. }
{$if (NOPE_RIGHT_ONLY <> 3) and declared(NOPE_RIGHT_ONLY)}
{$endif}
begin WriteLn('this program must never be reached'); end.
