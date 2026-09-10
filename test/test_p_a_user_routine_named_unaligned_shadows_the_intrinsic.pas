{ A user routine named `unaligned` SHADOWS the intrinsic, and fpc agrees.

  `unaligned` lexes as a plain identifier, so it is dispatched on the NAME in
  both the expression and the statement parser. Every other soft intrinsic in
  those chains is guarded so a user declaration wins, and this asserts that this
  one is too. Measured against fpc 3.2.2: it compiles this program and prints 6,
  so the shadow is FPC's behaviour and not a latitude we are taking.

  THE ROW DISCRIMINATES: without the guard the passthrough fires, the call is
  read as the intrinsic, and the answer is 5 rather than 6 -- a silently wrong
  value from a program that compiles clean, not a diagnostic. It is a separate
  file from test_p_unaligned_is_a_transparent_lvalue.pas because the
  declaration shadows for the whole program, so the two claims cannot share
  one.
  umbrella-pxx-compiles-fpc-itself }
program test_p_a_user_routine_named_unaligned_shadows_the_intrinsic;

var
  fails: LongInt;

function unaligned(x: LongInt): LongInt;
begin
  unaligned := x + 1;
end;

begin
  fails := 0;
  if unaligned(5) = 6 then
    WriteLn('R01 user routine wins ok')
  else
  begin
    WriteLn('R01 user routine wins FAIL got=', unaligned(5), ' want=6');
    fails := fails + 1;
  end;
  WriteLn('fails=', fails);
  WriteLn('UNALIGNEDSHADOW OK');
end.
