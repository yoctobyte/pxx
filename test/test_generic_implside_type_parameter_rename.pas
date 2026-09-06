program test_generic_implside_type_parameter_rename;
{$mode objfpc}
{ A generic ROUTINE whose implementation renames the type parameter is ACCEPTED.
  A deliberate divergence, asserted here rather than described in a skip line.

  WHY IT NEEDED A TEST OF ITS OWN. tgenfunc17 and tgenfunc18 are the corpus rows
  for this, and both are UNIT sources -- which pxx cannot compile standalone, so
  it refuses them for that reason alone and their `{ %FAIL }` was satisfied
  without the compiler ever reaching the construct. Their skip lines described a
  dialect-pass the run never demonstrated. Auto-gating unit sources removed the
  vacuous pass and would have removed the claim with it; this keeps the claim and
  makes it fail if the behaviour changes.

  SAFE ONLY WHILE A GENERIC ROUTINE TAKES ONE TYPE PARAMETER: a SWAP could
  mislead where a rename cannot, and is unreachable today
  (bug-p-a-generic-routine-supports-exactly-one-type-parameter). RE-MEASURE IF
  THAT LANDS.

  The METHOD form is NOT this rule and is measured to differ: `generic function
  TR.Id<S>` against a `<T>` declaration is REJECTED with `unknown type: S`. Only
  the routine-in-a-unit shape is accepted, which is exactly what the two corpus
  rows are. }
uses urename;
begin
  WriteLn(specialize Id<Integer>(42));
  WriteLn(specialize Id<String>('ok'));
end.
