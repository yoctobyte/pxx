program test_p_a_real_error_directive_still_halts;
{ THE CONTROL THAT MUST NOT COMPILE. Gating `{$error}` on the pre-pass trades a
  false halt for a silent one if the real pass stops raising it too, and that
  would be the worse defect of the two -- `{$error}` exists to stop a build.
  NOPE_REAL_ERROR is in the text so the Makefile row can assert the message
  still carries it. }
begin
{$error NOPE_REAL_ERROR}
end.
