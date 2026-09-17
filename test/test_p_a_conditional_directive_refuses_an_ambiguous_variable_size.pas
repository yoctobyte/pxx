program test_p_a_conditional_directive_refuses_an_ambiguous_variable_size;
{ THE CONTROL THAT MUST NOT COMPILE, and it guards the design of the fix beside
  it rather than the fix itself.

  Sizing a variable from a conditional directive means walking the token stream
  for `NAME : TYPE`, and that walk HAS NO SCOPE. One name can be a local in two
  procedures, a record field, and a parameter, all in one file, and nothing in
  the token stream says which declaration a directive sits inside. So the walk
  collects every match and DECLINES the moment two disagree.

  Here `NOPE_AMBIGUOUS_SIZE` is a record field of type byte and a variable of
  type int64. fpc compiles this and answers correctly, because it has scopes.
  We refuse. That is the same trade the explicit-value enum walk makes next
  door: a wrong size in a conditional does not produce a wrong value, it
  produces a DIFFERENT PROGRAM, and a differing diagnostic is deferred.

  The name is in the message so the Makefile row can assert the refusal still
  carries the operand it could not read -- without that, the reader is sent
  looking at the directive instead of at the two declarations. }
type
  nopeholder = record NOPE_AMBIGUOUS_SIZE: byte; end;
var
  NOPE_AMBIGUOUS_SIZE: int64;
{$if sizeof(NOPE_AMBIGUOUS_SIZE) = 8}
const R = 'TOOK THE VAR -- the walk guessed between two declarations';
{$else}
const R = 'TOOK THE FIELD -- also a guess, and silently';
{$endif}
begin
  WriteLn(R);
end.
