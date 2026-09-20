program test_dce_sweep_thunk_abi;
{ WHAT THIS PINS, and it is an ASYMMETRY rather than a value: on riscv32 and
  on call0 xtensa a sweep thunk produces a CodeRef target INSIDE this body,
  which DceRangeHoldsStub then makes a root; on WINDOWED xtensa
  TargetHasSweepThunk is false (ir_codegen.inc, the XTENSA_ABI_WINDOWED arm --
  windowed keeps sp constant and a0 is the live return address, so a thunk has
  nowhere to put either), the sweep is inlined at every return, and there is no
  in-body target at all.

  THE TWO ARMS ARE EACH OTHER'S CONTROL. Same ISA, same source, one flag: a run
  where BOTH report the same count is the instrument having stopped measuring,
  and a run where windowed reports an in-body target is a real change in what
  DCE can see. That asymmetry is what answered
  bug-a-riscv32-dce-keeps-135-more-bodies-than-xtensa-on-one-program --
  xtensa's smaller live set is an ABI consequence, NOT a pass running blind.

  Three managed locals (SWEEP_THUNK_MIN_SLOTS = 3) and TWO returns, which is
  what makes EmitProcScopeExitCleanupForTarget place an out-of-line sweep
  thunk on the second return rather than inlining the sweep. The thunk lands
  AFTER that return, i.e. inside the body and not at its entry, and the call
  to it is a CodeRef whose target is mid-body -- the shape the riscv32/xtensa
  body-count question is about. }
function F(n: Integer): Integer;
var a, b, c: AnsiString;
begin
  a := 'aaaa'; b := 'bbbb'; c := 'cccc';
  if n > 0 then
  begin
    F := Length(a) + Length(b) + Length(c);
    Exit;
  end;
  F := Length(a) - Length(b) - Length(c);
end;
begin
  WriteLn(F(1) + F(-1));
end.
