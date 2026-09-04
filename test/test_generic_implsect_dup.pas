{ A program specializing the SAME template a used unit already specialized in
  its IMPLEMENTATION section. Both mint the alias `TBox$Integer`; the unit's row
  is private to it and the program's is the program's.

  REGRESSION, and it was a SEAM rather than either change alone. Two commits on
  one day: Track D's interface/implementation boundary taught the declaration
  tables which section a row was declared in, and this slice's shadowing fix
  taught ParseSpecialization to treat "an exact re-statement is a no-op" as a
  question about the TEMPLATE INDEX. Neither is wrong. What broke is that
  FindSpecialization -- a VISIBILITY check whose own comment already explains
  why it has to be one -- still had only the UNIT half of the answer:

    FindSpecialization  saw ugimpb's private row  -> "exact re-statement, skip"
    FindUClass          refused ugimpb's private row -> unknown type

  So the program's own declaration was never emitted and `var b: TBox<Integer>`
  answered `unknown type: TBox$Integer`. ONE DECLARATION, TWO VISIBILITY CHECKS,
  DISAGREEING -- which is worse than either rule alone, because the permissive
  one silently suppressed the work the strict one then demanded.

  Fixed by asking the question once: Specializations[] gained the same
  section stamp every other declaration table has, and FindSpecialization uses
  DeclVisibleSect.

  The three columns are three different scopes for one alias string: 42 is the
  program's own specialization, 202 is ugimpb's private one reached only through
  its interface's Integer, and SizeOf(b.V) = 4 says which argument won. FPC
  3.2.2 prints the same line.

  MEASURED, and here is exactly what was measured rather than reconstructed.
  This shape passed on the PIN (42 202 4) and passed at 8f441595b. At origin
  with Track D's commit pulled and before the FindSpecialization change it
  answered `unknown type: TBox$Integer`; after it, 42 202 4 again. So the window
  in which it failed is one afternoon on origin, and this test reads as "still
  correct" rather than "newly correct". }
program test_generic_implsect_dup;
{$MODE DELPHI}

uses ugimpa, ugimpb;

var
  b: TBox<Integer>;
begin
  b.V := 42;
  writeln(b.V, ' ', MakeB, ' ', SizeOf(b.V));
end.
