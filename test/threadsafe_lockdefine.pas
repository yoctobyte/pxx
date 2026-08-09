{ The heap-lock defines PasApplyTargetDefines picks per target.

  PXX_TS_HARDLOCK is set at exactly one place, guarded on x86-64 — and that
  place sat BELOW an `if TargetArch = TARGET_X86_64 then Exit`, so the
  condition was unsatisfiable and the define was dead on EVERY build. x86-64
  --threadsafe therefore ran PXXRecordRelease during class finalization, which
  races the allocator and is precisely what the define exists to prevent.
  bug-a-x86-64-early-exit-skips-target-defines

  Both spellings are asserted by the Makefile: with only the ON case, a define
  set unconditionally would pass. }
program threadsafe_lockdefine;
begin
{$ifdef PXX_TS_HARDLOCK}
  WriteLn('hardlock');
{$else}
  WriteLn('no-hardlock');
{$endif}
{$ifdef PXX_TS_SOFTLOCK}
  WriteLn('softlock');
{$else}
  WriteLn('no-softlock');
{$endif}
end.
