{ The terminal arm of the {$...} dispatch, which did not exist before
  2026-09-04: any directive outside the ~40 the chain names was consumed and
  discarded -- no warning, no note, exit 0 -- so a MISSPELLING silently got the
  default behaviour of whatever it meant to change.

  THREE POPULATIONS IN ONE FILE, COUNTED SEPARATELY, AND THE THIRD IS WHY.
  The failure value here is SILENCE, so "the inert block stayed quiet" is a row
  that passes on a compiler saying nothing about anything -- i.e. on the bug.
  And a warning that fires on {$H+} would be switched off within a day, taking
  the misspelling case with it. So the file asserts both directions at once:
  two must be reported as unknown, three as recognised-but-unimplemented, and
  the TOTAL must be exactly five, which is the only assertion that can catch an
  inert directive starting to warn.
  bug-p-an-unknown-compiler-directive-is-silently-ignored }
program test_pascal_directive_unknown_warns;

{ Silent: recognised and inert -- ignoring these leaves pxx doing what the
  source asked, or something strictly more permissive. }
{$H+}{$modeswitch advancedrecords}{$apptype console}{$macro on}{$INLINE ON}
{$codepage utf8}{$warn 5024 off}{$push}{$pop}{$Q-}{$I+}{$WRITEABLECONST ON}
{$BOOLEVAL OFF}{$LONGSTRINGS ON}{$goto on}{$pointermath on}{$region hdr}
{$endregion}{$X-}{$T+}{$V+}{$smartlink on}

{ Class 2 -- pxx does not know the name at all. The first is one letter off
  from a directive that changes record layout, which is the whole reason this
  arm exists. }
{$PACKRECRDS 1}
{$definitelynotadirective}

{ Class 1 -- FPC gives these meaning, pxx does not implement them, and ignoring
  one changes the layout or the evaluation the source asked for. }
{$PACKENUM 1}
{$H-}
{$BOOLEVAL ON}

begin
  WriteLn('ok');
end.
