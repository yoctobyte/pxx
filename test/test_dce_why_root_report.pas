program test_dce_why_root_report;
{ POSITIVE CONTROL FOR --dce-why. The report says WHY each live body survived
  the pass, and a report that cannot be wrong about a body whose root is known
  cannot be trusted about one whose root is the question -- which is the whole
  reason it exists (the NilPy ESP image has 819,480 B rooted as "holds a stub
  target" and nobody could see that before).

  Two bodies with KNOWN and DIFFERENT roots, and the point is that each is
  reached exactly one way:

    RootedByVmt   -- a virtual method, never called by name anywhere. The only
                     thing that names it is the VMT slot, so the report must
                     say `vmt/rtti slot`.
    RootedByCall  -- an ordinary routine called once, from `Driver`, and its
                     address is never taken. The report must say it reached a
                     root THROUGH Driver -- `RootedByCall <- Driver <- [called
                     from unowned code]` -- and not call it a root itself.
                     Driver exists so the assertion is about the CHAIN and not
                     only about the first hop: called straight from the main
                     body, RootedByCall is one hop from a root and a report
                     that only ever printed one hop would still pass.

  The Makefile row greps for exactly those two lines. It is a compile-time
  assertion about the REPORT; the program's own output is asserted too, so a
  build that reports beautifully and computes wrongly still fails. }
{$mode objfpc}
type
  TBase = class
    function Tag: Integer; virtual;
  end;
  TDerived = class(TBase)
    function Tag: Integer; override;
  end;

function TBase.Tag: Integer;
begin
  Result := 1;
end;

{ NEVER named outside the VMT: the call below goes through a TBase-typed
  variable, so no call site mentions TDerived.Tag. }
function TDerived.Tag: Integer;
begin
  Result := 2;
end;

{ RECURSIVE ON PURPOSE. Written as `Result := n * 7` this body is INLINED at
  the default -O and then correctly DROPPED -- the program still prints 42 and
  the report says nothing, which is exactly the silence a broken filter would
  produce. So the control has to be a body the inliner will not take, or it
  tests the inliner instead of the report. Measured 2026-09-20: the flat form
  reports `RootedByCall <- DROPPED`, this one reports `called by`. }
function RootedByCall(n: Integer): Integer;
begin
  if n <= 0 then
    Result := 0
  else
    Result := 7 + RootedByCall(n - 1);
end;

{ Self-recursive for the same reason RootedByCall is. }
function Driver(n: Integer): Integer;
begin
  if n > 1 then
    Driver := Driver(n - 1)
  else
    Driver := RootedByCall(6);
end;

var b: TBase;
begin
  b := TDerived.Create;
  WriteLn('tag ', b.Tag);
  WriteLn('call ', Driver(2));
  b.Free;
end.
