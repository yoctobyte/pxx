{ The SPELLING half of bug-p-after-a-nested-routine-is-lifted-a-later-syntax-error-names-the-wrong-token.
  Once any nested routine has been lifted, every LATER syntax error read its
  token spelling and its `near:` window from the slots the deleted body used to
  occupy, so this file reported `expected 'then' before 'q'` with a window from
  TC.Later's header -- the right LINE, the wrong token, eleven positions early.
  Deleting the nested routine made the identical error read correctly, which is
  what pinned it to the lift rather than to the expression parser.

  THIS FILE MUST NOT COMPILE. The Makefile asserts the diagnostic TEXT; a
  compile-only row cannot see a wrong spelling, and a row asserting only the
  LINE cannot either -- the line was right all along and is what made this look
  cosmetic. }
{$mode objfpc}
program test_a_lifted_nested_routine_keeps_its_token_channels_diag;
type TC = class F: Integer; procedure Outer; procedure Later; end;
procedure TC.Outer;
  procedure Helper(AVeryDistinctiveName: Integer);   { captures F -> lifted }
  begin F := F + AVeryDistinctiveName; end;
begin Helper(1); end;
procedure TC.Later;
var q: Integer;
begin
  q := 1;
  if q 2 then WriteLn('x');       { the deliberate syntax error: before '2' }
end;
var c: TC;
begin c := TC.Create; c.Outer; end.
