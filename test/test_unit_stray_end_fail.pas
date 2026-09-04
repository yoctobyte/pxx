program test_unit_stray_end_fail;
{ Must NOT compile: the unit it uses has a spare top-level `end`. The pinned
  compiler builds this and prints `a` -- which is what made this the invisible
  half of the class. }
uses unit_stray_end;
begin
  StrayA;
end.
