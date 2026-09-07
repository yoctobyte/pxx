program test_managed_sweep_thunk;
{ THE SHAPE THE PER-PROCEDURE SWEEP THUNK FIRES ON, which is not the shape the
  other two leak tests have.

  On x86-64 the scope-exit release sweep is emitted ONCE per body, out of line,
  and CALLed from the second return onward (EmitProcScopeExitCleanupForTarget,
  ir_codegen.inc). The thunk is placed only when a body has at least two
  returns AND at least SWEEP_THUNK_MIN_SLOTS releasable slots.

  test_unnamed_managed_temps_are_released.pas and test_open_array_no_leak.pas
  have NEITHER, and that is why this file exists rather than a bound being
  tightened on one of those. Measured when the thunk landed: both of them
  compile to BYTE-IDENTICAL binaries with and without the change, so their
  census is flat because nothing was compiled differently -- a control drawn
  from a population the question is not about. A flat number from an unchanged
  binary certifies nothing.

  Risky() below has four managed locals and three return points, one of them
  reached by falling out of the body, plus a raise so the exception landing
  pad's OWN copy of the sweep is exercised in the same body. The pad keeps its
  inline copy (it re-raises and never returns), so this asserts the two coexist.

  A census row and not an expect_same row, for the reason the whole family
  exists: a leak does not corrupt. Every WriteLn here is correct with the
  releases removed. }
var
  gS: AnsiString;
  i, caught, ok: Integer;

function Risky(n: Integer): AnsiString;
var a, b, c, d: AnsiString;
begin
  a := 'aa'; b := 'bb'; c := 'cc'; d := 'dd';
  a := a + b;
  c := c + d;
  if (n mod 4) = 0 then begin Risky := a; Exit; end;
  if (n mod 4) = 1 then begin Risky := c; Exit; end;
  if (n mod 4) = 2 then raise (Length(a) + 10);
  Risky := a + c;
end;

begin
  caught := 0; ok := 0;
  for i := 1 to 20000 do
  begin
    try
      gS := Risky(i);
      ok := ok + Length(gS);
    except
      caught := caught + 1;
    end;
  end;
  writeln('SWEEPTHUNK OK ok=', ok, ' caught=', caught);
end.
