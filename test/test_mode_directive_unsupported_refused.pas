program test_mode_directive_unsupported_refused;
{ MUST NOT COMPILE. `{$MODE MACPAS}` names a dialect pxx does not implement, and
  the front door is where that gets said.

  Owner decision 2026-09-05, decide-which-pascal-dialects-pxx-targets: pxx
  targets the FPC and Delphi dialects; the rest are DEFERRED, not refused, and
  live in rainy-day/. A deferred dialect still has to be REJECTED, because the
  alternative is what this replaced -- the whole handler was
  `DelphiMode := CaseEqual(name, 'delphi')`, so every other value fell into one
  bucket and compiled silently. For MacPas that is a wrong PROGRAM and not a
  missing feature: `{$ifc}`/`{$elsec}`/`{$endc}` are unrecognised, both arms of
  the conditional compile, and the binary is not the one written.

  The positive direction is asserted by the whole rest of the suite -- every
  test and every lib/rtl unit carries {$mode objfpc}, {$mode delphi} or
  {$MODE PXX}, so a refusal that was too wide could not survive one build. This
  row is the half that has no other witness. }
{$MODE MACPAS}
begin
end.
