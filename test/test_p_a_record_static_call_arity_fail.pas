{ MUST NOT COMPILE. The four bad shapes at the advanced-record ctor / `static`
  method call arm — the third hand-rolled argument loop, which had no arity
  check at all.

  Measured 2026-09-09 before the fix, and these are the values the broken
  compiler produced, not merely "it was accepted":

      TR.One(1, 2, 3)   -> 3    the arguments shifted one slot
      TR.One()          -> 12   uninitialised memory, exit 0, no diagnostic

  fpc 3.2.2 refuses all four rows.

  ALL FOUR ARE IN ONE FILE BECAUSE THESE COME FROM ErrorRecover, NOT Error —
  the arity pre-check reports and carries on, so every bad row is found in one
  pass. That is deliberate and it is what the count asserts: a fix that made
  one row halt would take the other three with it and the count would drop,
  which a `!` on the compiler alone could not see.

  THE ACCEPT SIDE IS test_p_a_record_static_call_is_checked_like_every_other_call
  AND IT CANNOT FAIL FOR THIS DEFECT — it is byte-identical on the pinned
  compiler, because the broken loop got the GOOD calls right. It is a
  must-not-break control for selfBase and nothing more. THIS file is the one
  with a positive control: the pin compiles it, exit 0, no diagnostics.

  bug-p-the-record-static-call-arm-is-a-third-hand-rolled-argument-loop }
{$mode objfpc}{$modeswitch advancedrecords}
program test_p_a_record_static_call_arity_fail;
type
  TR = record
    x, y: Integer;
    class function One(a: Integer): Integer; static;
    constructor Create(ax, ay: Integer);
  end;

class function TR.One(a: Integer): Integer; begin One := a; end;
constructor TR.Create(ax, ay: Integer); begin x := ax; y := ay; end;

var n: Integer; r: TR;
begin
  n := TR.One(1, 2, 3);     { static, surplus  — answered 3 }
  n := TR.One();            { static, none     — answered 12 }
  r := TR.Create(1, 2, 3);  { ctor,   surplus }
  r := TR.Create(1);        { ctor,   too few }
  WriteLn(n, r.x);
end.
