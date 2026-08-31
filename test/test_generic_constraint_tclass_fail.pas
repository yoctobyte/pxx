{ A `T: class` constraint must reject `TClass`, the METACLASS.

  A class reference is not a class instance type, which is what `T: class`
  asks for. TClass is not in the class table either (ParseTypeKind lowers a
  bare TClass to tyPointer with a tyClass element), so it took the same
  not-declared-yet exit as LongInt above.
  fpc 3.2.2 refuses this too (fpc-testsuite tgenconstraint5, marked %FAIL). }
program test_generic_constraint_tclass_fail;
{$mode delphi}
type
  TNeedsClass<T: class> = class
  end;
  TBad = TNeedsClass<TClass>;
begin
end.
