{ {$R+} MUST TRAP IN A PROGRAM THAT NEEDS NOTHING ELSE FROM THE RUNTIME.

  The range-check helper, PXXRangeChkI64, lives in builtinheap. Since
  523833fde3 (2026-09-22) that unit is appended only on evidence, and {$R+}
  was not on the evidence list. Both emitters then fell through to a silent
  passthrough when the helper was absent, so this program BUILT, stored 44 for
  300, and exited 0. Nothing in it needs the heap, which is the whole point:
  there are no strings, no arrays and no concatenation, only a narrowing store.
  Any of those would pull the unit in and hide the defect.

  The {$R-} store first is the control: it must wrap, so a check that fired
  everywhere would fail that row. }
program test_range_checks_fire_in_a_program_with_no_strings;
var b: Byte; i: LongInt;
begin
  i := 300;
{$R-}
  b := i;
  WriteLn(b);
{$R+}
  b := i;
  WriteLn(b);
end.
