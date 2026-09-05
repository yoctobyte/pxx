program test_varrec_format_rejects_fail;
{ %FAIL-style negative, and it is frankB's condition on phase 2 of
  feature-writeln-as-library: the loosening that lets `[ x:8:2 ]` parse inside an
  `array of const` literal must NOT have loosened the ordinary call-argument
  path. A stray `:` in a plain non-variadic call must still error.

  Drawn from the population the change touches -- an argument list -- rather
  than from somewhere a colon could never have reached, which would pass on both
  sides of the change and certify nothing. Three more shapes are asserted as
  still-refused in the Makefile beside this one (array index, set constructor,
  a third colon), and the accepted spelling has its own parity test; a loosening
  whose only evidence is that the new syntax works cannot tell you what else it
  started accepting. }
procedure Foo(a, b: Integer);
begin
end;
begin
  Foo(1:8, 2);
end.
