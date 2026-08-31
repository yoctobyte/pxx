{ A `T: class` constraint must reject a BUILTIN SCALAR argument.

  `LongInt` is not in the class table, which used to mean "not declared yet"
  and so was skipped -- the same observation that legitimately protects a class
  declared later in the section. But a builtin name is answered from a fixed
  table, not the symbol table, so it is settled now and stays settled.
  fpc 3.2.2 refuses this too (fpc-testsuite tgenconstraint4, marked %FAIL).
  bug-p-generic-constraints-are-checked-before-the-type-section-closes }
program test_generic_constraint_longint_fail;
{$mode delphi}
type
  TNeedsClass<T: class> = class
  end;
  TBad = TNeedsClass<LongInt>;
begin
end.
