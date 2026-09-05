program test_mode_directive_typo_refused;
{ MUST NOT COMPILE, and it is a SEPARATE row from the MacPas one on purpose:
  this is not about dialects at all.

  `{$MODE TOTALNONSENSE}` is a KNOWN directive carrying an unrecognised VALUE.
  The unknown-directive warning that landed 2026-09-04 keys on the directive
  NAME and cannot see it -- measured: `{$TOTALLYUNKNOWNDIRECTIVE}` warns,
  `{$MODE TOTALNONSENSE}` was completely silent. Different axis, which is why
  the mode handler needed its own reject arm rather than being wired into that
  warning.

  Keep this row even if the dialect list ever grows: a typo can never be in it,
  so this one asserts the arm exists at all. }
{$MODE TOTALNONSENSE}
begin
end.
