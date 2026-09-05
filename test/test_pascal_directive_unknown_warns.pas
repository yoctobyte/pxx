{ The terminal arm of the {$...} dispatch, which did not exist before
  2026-09-04: any directive outside the ~40 the chain names was consumed and
  discarded -- no warning, no note, exit 0 -- so a MISSPELLING silently got the
  default behaviour of whatever it meant to change.

  THREE POPULATIONS IN ONE FILE, COUNTED SEPARATELY, AND THE THIRD IS WHY.
  The failure value here is SILENCE, so "the inert block stayed quiet" is a row
  that passes on a compiler saying nothing about anything -- i.e. on the bug.
  And a warning that fires on {$H+} would be switched off within a day, taking
  the misspelling case with it. So the file asserts both directions at once:
  the unknown rows, the unimplemented rows and the TOTAL are asserted
  separately; the total is the only one that can catch an inert directive
  starting to warn, and the counts live in the Makefile rather than here so a
  comment cannot drift into being read as the census.
  bug-p-an-unknown-compiler-directive-is-silently-ignored }
program test_pascal_directive_unknown_warns;

{ Silent: recognised and inert -- ignoring these leaves pxx doing what the
  source asked, or something strictly more permissive. }
{$H+}{$modeswitch advancedrecords}{$apptype console}{$macro on}{$INLINE ON}
{$codepage utf8}{$warn 5024 off}{$push}{$pop}{$Q-}{$I+}{$WRITEABLECONST ON}
{$BOOLEVAL OFF}{$LONGSTRINGS ON}{$goto on}{$pointermath on}{$region hdr}
{$endregion}{$X-}{$T+}{$V+}{$smartlink on}

{ The name-axis sweep of 2026-09-05: names fpc 3.2.2's OWN sources use that this
  tree never spelled, so the present-tense census could not see them and each
  one warned on code fpc accepts. They are here rather than only in the list
  because the TOTAL below is the only assertion that can catch one of them
  starting to warn again. }
{$asmcpu 386}{$copyright me}{$hugecode on}
{$hugepointerarithmeticnormalization on}
{$hugepointercomparisonnormalization on}
{$minstacksize 16384}{$screenname test}

{ Class 2 -- pxx does not know the name at all. The first is one letter off
  from a directive that changes record layout, which is the whole reason this
  arm exists. }
{$PACKRECRDS 1}
{$definitelynotadirective}

{ Class 1 -- FPC gives these meaning, pxx does not implement them, and ignoring
  one changes the layout or the evaluation the source asked for.

  PACKENUM AND H- USED TO BE THIS BLOCK AND ARE NOW IMPLEMENTED, which is why
  the counts below moved: a class-1 row is a claim that we do NOT do the thing,
  so it goes stale by the feature landing rather than by anything breaking. The
  block is re-populated instead of shrunk, because a class-1 population of one
  cannot distinguish "the classifier works" from "the classifier answers 1 for
  everything it is asked". }
{$PACKSET 1}
{$BITPACKING ON}
{$CALLING stdcall}
{$BOOLEVAL ON}

begin
  WriteLn('ok');
end.
