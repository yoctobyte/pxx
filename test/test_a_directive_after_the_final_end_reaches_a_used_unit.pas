program test_a_directive_after_the_final_end_reaches_a_used_unit;
{ feature-p-assertions-switch-and-strict-default -- the baseline a used unit is
  reset FROM.

  The {$ASSERTIONS ON} at the bottom of this file sits AFTER the final `end.`.
  fpc does not compile that text at all. pxx lexes the whole main file before
  the parser reaches the `uses`, and a root-level `uses` used to RE-SNAPSHOT the
  directive baseline from whatever the lexer had ended up holding -- which is
  the state at END OF FILE, not at the `uses`. So this line re-armed the used
  unit's Assert under --no-assertions, and the run printed `on`.

  RUN UNDER --no-assertions BY THE MAKEFILE, which is the only command line that
  can fail here: under the default the answer is `on` either way and the row
  would certify the bug. fpc with no flags prints `off` (measured 2026-09-09 in
  a clean directory -- fpc reuses a .ppu built under a different -Sa, so a stale
  unit cache answers for the wrong command line and did once here).

  Assertions are the CHEAPEST member of this family, not the worst: the same
  eleven values carry {$PACKRECORDS}, so the identical line written as
  {$PACKRECORDS 1} was a RECORD LAYOUT in a unit that never asked. }

uses uassertambient;

begin
  WriteLn('unit-ambient=', uassertambient.AssertState);
end.
{$ASSERTIONS ON}
