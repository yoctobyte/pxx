program test_generic_impl_template_is_private_fail; {$MODE DELPHI}
{ The NEGATIVE half. THidden is declared in ugvis's IMPLEMENTATION section, so
  naming it here must be refused. Before the fix this compiled and ran, and
  which template it bound depended on the ORDER OF THE USES CLAUSE. }
uses ugvis;
var q: THidden<Integer>;
begin q.V := 9; WriteLn('LEAKED ', q.V); end.
