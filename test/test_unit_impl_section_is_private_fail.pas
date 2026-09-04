program test_unit_impl_section_is_private_fail;
{ The NEGATIVE half. Four kinds of private name, four independent diagnostics,
  because the leak was never one table with a hole: types, consts, routines and
  vars each had their own lookup and every one of them ignored the section.
  Fixing one and closing the ticket would leave three open, so all four are
  asserted here rather than one standing in for the rest.
  Each reference stands alone -- no `var r: TImplOnlyRec`, because a broken
  declaration makes every later use of `r` a CASCADE and the run then reports
  one root error plus noise instead of four independent ones. }
uses unit_impl_private;

begin
  WriteLn(SizeOf(TImplOnlyRec));
  WriteLn(ImplOnlyRoutine);
  WriteLn(IMPL_ONLY_CONST);
  WriteLn(ImplOnlyVar);
end.
