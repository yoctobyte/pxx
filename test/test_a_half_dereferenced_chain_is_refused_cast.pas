program test_a_half_dereferenced_chain_is_refused_cast;
{ NEGATIVE HALF, cast spelling -- the sibling of
  test_a_half_dereferenced_chain_is_refused_var, and NOT the same code path.

  It reaches a DIFFERENT builder: the shared selector walker's, not
  ParseLValueAST's, and it arrives there with the ultimate base record already
  in hand, so both RequireValueHasMembers and RequireRecMember pass. Neither can
  catch this -- they ask about the RECORD, and the record is fine; what is wrong
  is that we are not at it yet. Fixing only the variable spelling left this one
  answering 4306200 in silence, which is why both halves are asserted.
  bug-p-a-half-dereferenced-pointer-chain-answers-garbage-instead-of-refusing }
{$mode delphi}
type
  TRec = record a, b: Integer; end;
  PRec = ^TRec; PPRec = ^PRec; PPPRec = ^PPRec;
var
  r: TRec; p: PRec; pp: PPRec; ppp: PPPRec;
begin
  r.a := 11; r.b := 22; p := @r; pp := @p; ppp := @pp;
  WriteLn(PPPRec(ppp)^.a);
end.
