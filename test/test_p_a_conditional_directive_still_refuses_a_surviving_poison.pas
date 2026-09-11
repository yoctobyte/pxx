program test_p_a_conditional_directive_still_refuses_a_surviving_poison;
{ THE OTHER HALF OF THE CONTROL: a comparison nothing short-circuits away must
  still raise, in the SAME words and naming the SAME operand as before the
  deferral existed. This is the shape the message was written for -- measured
  2026-09-05 on FPC's cfileutl.pas, `{$if FPC_FULLVERSION < 20701}` under an
  invocation with no fpc define profile, where the cause was one absent define
  and the fix was a compiler FLAG.
  If this row ever goes green, the fix stopped deferring and started guessing. }
{$if NOPE_SURVIVING < 20701}
{$endif}
begin WriteLn('this program must never be reached'); end.
