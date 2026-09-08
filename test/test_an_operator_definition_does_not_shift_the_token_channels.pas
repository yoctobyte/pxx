{ MUST NOT COMPILE. ParseOperatorDef splices a synthesized `function <synName>`
  header in front of the parameter list with a hand-written, field-by-field
  `Tokens[j + 2] := Tokens[j]` loop -- open-coded rather than routed through
  InsertTokens, so ShiftTokParallel never ran and the thirteen token-parallel
  arrays stayed where they were. Every token after an `operator` definition then
  read its SPELLING from the slot two positions along.

  THE MAGNITUDE IS THE EVIDENCE and it is why this file's sibling exists: this
  form was reported `expected 'then' before 'WriteLn'`, exactly TWO tokens late,
  which is the insert width. The named-result form
  (..._named.pas) also REMOVES one token and was off by one, `before 'then'`.
  Two movers, two offsets, one correct answer -- a single arm cannot tell a fix
  of both from a fix of either.

  The error must name '2' and the window must sit on it. A compile-only row
  cannot see a wrong spelling, and a row asserting the LINE cannot either: the
  line was right throughout, which is what makes this class look cosmetic.
  bug-p-after-a-nested-routine-is-lifted-a-later-syntax-error-names-the-wrong-token }
{$mode objfpc}
program test_an_operator_definition_does_not_shift_the_token_channels;
type TB = record V: LongInt; end;
operator := (a: LongInt): TB;
begin Result.V := a; end;
procedure Later;
var q: Integer;
begin
  q := 1;
  if q 2 then WriteLn('x');       { deliberate: expected 'then' before '2' }
end;
begin Later; end.
