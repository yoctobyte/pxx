program test_diag_a_bodiless_routine_that_swallows_the_main_block_fail;
{ `procedure A;` with no body and no forward: B parses as A's nested routine and
  the main block as A's body, so `end.` arrives where the main `begin` belongs.
  The error must say so, not just `expected 'begin' before '.'`.
  bug-p-a-bodiless-procedure-declaration-is-accepted-and-swallows-the-next-routine }
procedure A;

procedure B;
begin
  WriteLn(1);
end;

begin
  B;
end.
