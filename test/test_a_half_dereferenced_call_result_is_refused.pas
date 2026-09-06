{ The NEGATIVE half of the call-result implicit deref, and the THIRD builder.

  `GetPPP^.a` on a three-deep pointer is TWO dereferences short. fpc 3.2.2
  refuses it with `Illegal qualifier` (asserted against the oracle, not
  assumed), and pxx must refuse it too: resolving it would mean accepting what
  fpc rejects on a construct only a mistake produces, and returning the ultimate
  record for a half-dereferenced pointer is exactly how a wrong offset becomes a
  plausible value.

  A third file because it is a third OPENER: the variable spelling reaches
  ParseLValueAST's builder, the cast spelling the shared walker's, and this one
  arrives through ApplyCallResultPtrSuffix. All three now read a declared depth,
  from three different tables, and the gate is what keeps this line out.

  The positive half is
  test_a_call_result_takes_the_implicit_deref_at_pointer_depth_2.
  bug-p-a-call-result-at-pointer-depth-2-does-not-take-the-implicit-deref }
{$mode delphi}
program test_a_half_dereferenced_call_result_is_refused;
type TRec = record a, b: Integer; end;
     PRec = ^TRec; PPRec = ^PRec; PPPRec = ^PPRec;
var r: TRec; p: PRec; pp: PPRec; ppp: PPPRec;
function GetPPP: PPPRec; begin Result := ppp; end;
begin
  r.a := 11; p := @r; pp := @p; ppp := @pp;
  WriteLn(GetPPP^.a);
end.
