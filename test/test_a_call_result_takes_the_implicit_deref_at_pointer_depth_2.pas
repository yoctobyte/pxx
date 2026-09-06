{ A `.` on a CALL RESULT that is still a pointer must take the implicit
  dereference, at every declared depth -- the third opener, after the plain
  variable and the typed pointer cast.

  ResolveNodeRec walks a deref chain down to whatever it bottoms out on and
  requires the count to equal the DECLARED depth. It knew two node kinds,
  AN_IDENT and AN_PTR_CAST, and a call result bottoms out on AN_CALL -- so it
  answered REC_NONE and the shared walker's implicit-deref arm declined a chain
  that was perfectly well formed. The observable was a FALSE REFUSAL on a
  program fpc 3.2.2 compiles and runs.

  Rows A/B are the depth-1 opener, which was correct throughout and is the
  control that says the axis is DEPTH and not the call.
  Rows C..E are the depth-2 chain in all three member kinds: a field, a METHOD
  and a PROPERTY. A fields-only fix passes C and still calls the method with a
  pointer as Self, so E and D are not decoration.
  Row F is a late field -- offset 0 is what a lost base resolves to, so a probe
  on the first field cannot tell a correct answer from a dropped deref.
  Rows G/H are depth 3, full and one-short, which is where the depth GATE is
  actually exercised: one-short must resolve, and two-short must refuse. The
  refusal is the separate must-refuse test, without which this file passes just
  as well when the guard has been widened until nothing refuses.

  .expected is fpc 3.2.2's own output, byte for byte.
  bug-p-a-call-result-at-pointer-depth-2-does-not-take-the-implicit-deref }
{$mode delphi}
program test_a_call_result_takes_the_implicit_deref_at_pointer_depth_2;
type
  TRec = record
    a, b, c, d, e: Integer;
    function Doubled: Integer;
    property PA: Integer read a;
  end;
  PRec = ^TRec; PPRec = ^PRec; PPPRec = ^PPRec;
function TRec.Doubled: Integer; begin Result := a * 2; end;
var r: TRec; p: PRec; pp: PPRec; ppp: PPPRec;
function GetP: PRec;     begin Result := p;   end;
function GetPP: PPRec;   begin Result := pp;  end;
function GetPPP: PPPRec; begin Result := ppp; end;
begin
  r.a := 11; r.b := 22; r.e := 55;
  p := @r; pp := @p; ppp := @pp;
  WriteLn('A ', GetP^.a);
  WriteLn('B ', GetP^.Doubled);
  WriteLn('C ', GetPP^.a);
  WriteLn('D ', GetPP^.Doubled);
  WriteLn('E ', GetPP^.PA);
  WriteLn('F ', GetPP^.e);
  WriteLn('G ', GetPPP^^^.a);
  WriteLn('H ', GetPPP^^.a);
  WriteLn('OK');
end.
