{ feature-a-pxx-threadsafe-conditional-define — PXX_THREADSAFE is set whenever
  --threadsafe is on, on EVERY target, and unset otherwise.

  This program is run both ways by the Makefile so that stays pinned.

  It used to have to sit ABOVE PasApplyTargetDefines' `if TargetArch =
  TARGET_X86_64 then Exit` or be dead on the default target. That early return
  is gone (bug-a-x86-64-early-exit-skips-target-defines) — it is now a scoped
  `if TargetArch <> TARGET_X86_64 then begin ... end` around the CPU-define swap
  it was written for, so nothing appended below it is dead any more. The lock
  defines that WERE dead are asserted by threadsafe_lockdefine.pas beside this. }
program threadsafe_define;
begin
{$ifdef PXX_THREADSAFE}
  WriteLn('threadsafe');
{$else}
  WriteLn('plain');
{$endif}
end.
