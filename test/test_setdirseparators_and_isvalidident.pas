{ Two sysutils functions fcl-passrc's pscanner.pp calls and lib/rtl did not
  have. Both are pure and both have a rule that is easy to get subtly wrong,
  so the rows are chosen to separate the correct rule from the plausible one:

  - IsValidIdent's non-strict dot is TOLERATED and does not restart the
    segment, so `A.` is valid with AllowDots and invalid with StrictDots, and
    `A.9` is invalid under StrictDots because the dot restarts there. Reading
    the documentation rather than fpc's loop gives the opposite answer on the
    first of those.
  - SetDirSeparators rewrites EVERY accepted separator, not just the first,
    and returns the empty string unchanged rather than a lone '/'.

  Every row is asserted against fpc 3.2.2 -Mobjfpc output.
  feature-pascal-corpus-passrc }
{$mode objfpc}
program test_setdirseparators_and_isvalidident;
uses sysutils;
begin
  WriteLn('[', SetDirSeparators('a\b/c\d'), ']');
  WriteLn('[', SetDirSeparators('\'), ']');
  WriteLn('[', SetDirSeparators('plain'), ']');
  WriteLn('[', SetDirSeparators(''), ']');
  WriteLn(IsValidIdent('Foo'), ' ', IsValidIdent('_a9'), ' ', IsValidIdent('9a'),
          ' ', IsValidIdent(''), ' ', IsValidIdent('a b'));
  WriteLn(IsValidIdent('A.B'), ' ', IsValidIdent('A.B', True), ' ',
          IsValidIdent('A.', True), ' ', IsValidIdent('A.', True, True), ' ',
          IsValidIdent('A.9', True, True), ' ', IsValidIdent('A.B', True, True));
end.
