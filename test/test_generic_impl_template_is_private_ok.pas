program test_generic_impl_template_is_private_ok; {$MODE DELPHI}
{ The POSITIVE half: everything that must still work after the visibility rule.
  An interface-declared template crosses the unit boundary, and the declaring
  unit's own use of its PRIVATE template is untouched. }
uses ugvis;
var q: TVisible<Integer>;
begin
  q.V := 42;
  WriteLn(q.V, ' ', OwnUse);
end.
