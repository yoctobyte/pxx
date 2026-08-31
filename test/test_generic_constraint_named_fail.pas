{ A NAMED-TYPE constraint (`T: TSomeClass`) must also reject a builtin scalar.

  The sibling _longint_fail / _tclass_fail tests cover the `class` flag; this
  one covers the named-constraint loop, which is a separate arm of the same
  change and would otherwise ship untested. A scalar can never satisfy a
  constraint naming a class or an interface.
  fpc 3.2.2: "class type expected, but got \"LongInt\"".
  bug-p-generic-constraints-are-checked-before-the-type-section-closes }
program test_generic_constraint_named_fail;
{$mode delphi}
type
  TSomeClass = class
  end;
  TNeedsSome<T: TSomeClass> = class
  end;
  TBad = TNeedsSome<LongInt>;
begin
end.
