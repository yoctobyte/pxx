{ feature-a-pxx-threadsafe-conditional-define — PXX_THREADSAFE is set whenever
  --threadsafe is on, on EVERY target, and unset otherwise.

  The define must sit ABOVE PasApplyTargetDefines' `if TargetArch =
  TARGET_X86_64 then Exit`, or it is dead on the default target — which is what
  the two lock defines below it still are
  (bug-a-x86-64-early-exit-skips-target-defines). This program is run both ways
  by the Makefile so that arrangement stays pinned. }
program threadsafe_define;
begin
{$ifdef PXX_THREADSAFE}
  WriteLn('threadsafe');
{$else}
  WriteLn('plain');
{$endif}
end.
