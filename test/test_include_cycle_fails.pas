program test_include_cycle_fails;
{ Recursive include expansion needs a brake: two files that include each other
  are a legal thing to WRITE and an infinite thing to expand. Must fail with a
  diagnostic, not run out of stack or memory. Compile-fail test — the Makefile
  asserts a non-zero exit (bug-a-a-nested-include-is-silently-dropped). }
{$I tinc_cycle_a.inc}
begin
end.
