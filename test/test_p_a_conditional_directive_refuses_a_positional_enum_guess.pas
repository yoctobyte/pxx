program test_p_a_conditional_directive_refuses_a_positional_enum_guess;
{ THE CONTROL THAT MUST NOT COMPILE. `(a, b := 5, c)` is legal FPC and makes
  POSITION STOP MEANING ORDINAL -- c is 6, not 2. A walk that counted commas
  would answer `c in [c]` with ordinal 2 against a mask built from the same
  wrong ordinal, agree with itself, and take a branch on a number that is not
  this program's.

  So the enum walk declines the whole declaration the moment it sees an explicit
  value, and the refusal must NAME the operand it could not read -- the reader
  is otherwise sent into the set constant, which is fine, rather than to the
  enum, which is not.

  fpc compiles this and answers correctly, because it has the real ordinals. We
  refuse. That is a differing diagnostic on a construct where guessing is the
  only alternative, and a conditional that takes the wrong branch is a DIFFERENT
  PROGRAM -- not a different value. NOPE_POSITIONAL is in the set's name so the
  Makefile row can assert the message still carries it. }
type
  NOPE_POSITIONAL_ENUM = (pa, pb := 5, pc);
const
  NOPE_POSITIONAL = [pc];
begin
{$if (pc in NOPE_POSITIONAL)}
  WriteLn('TOOK THE ARM -- the walk guessed an ordinal from a comma count');
{$else}
  WriteLn('TOOK THE ELSE -- also wrong, and silently');
{$endif}
end.
