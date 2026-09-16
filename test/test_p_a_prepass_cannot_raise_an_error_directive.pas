program test_p_a_prepass_cannot_raise_an_error_directive;
{ PasCondQuiet's own contract, stated where it is declared: the pre-pass "must
  not HALT there either -- the real pass is the authority and will raise the
  error itself". An `{$error}` in an arm the pre-pass reached ONLY because it
  could not evaluate the question is exactly that halt.

  THE VALUE ROW IS THE POINT AND IT IS NOT 0. An unresolved sizeof does not
  answer 0 -- probed directly, `{$if sizeof(X) = 0}` takes its ELSE arm too --
  so the whole expression answers False rather than comparing a zero. Which
  means the arm taken is the last one, whatever it holds, and a fixture asserting
  `= 0` would have recorded the wrong mechanism.

  Byte-identical to fpc 3.2.2, which answers 2. The must-STILL-fire control is a
  Makefile row beside this one: a genuine `{$error}` has to keep halting, or
  this fix trades a false error for a silent one. }
uses prepasserr_mid;
var fails: Integer;
begin
  fails := 0;
  if Which = 2 then WriteLn('LADDER=yes')
  else begin WriteLn('LADDER=NO got ', Which); Inc(fails); end;
  WriteLn('fails=', fails);
  WriteLn('PREPASSERR OK');
end.
