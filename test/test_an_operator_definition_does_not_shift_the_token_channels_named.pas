{ MUST NOT COMPILE. The other arm of
  test_an_operator_definition_does_not_shift_the_token_channels.pas: a NAMED
  operator result (`operator := (a: LongInt) r: TB;`) makes ParseOperatorDef
  REMOVE the `r :` pair as well as insert the synthesized header, and that
  removal is a second hand-written `Tokens[j] := Tokens[j + 1]` loop with the
  same missing ShiftTokParallel.

  Insert two, remove one, so this arm was off by exactly ONE where its sibling
  was off by two -- `expected 'then' before 'then'` against `before 'WriteLn'`.
  Keeping both is what separates a fix of the pair from a fix of either.
  bug-p-after-a-nested-routine-is-lifted-a-later-syntax-error-names-the-wrong-token }
{$mode objfpc}
program test_an_operator_definition_does_not_shift_the_token_channels_named;
type TB = record V: LongInt; end;
operator := (a: LongInt) r: TB;
begin r.V := a; end;
procedure Later;
var q: Integer;
begin
  q := 1;
  if q 2 then WriteLn('x');       { deliberate: expected 'then' before '2' }
end;
begin Later; end.
