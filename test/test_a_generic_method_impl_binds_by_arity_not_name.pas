program test_a_generic_method_impl_binds_by_arity_not_name;
{ See test/units/uarityoverload.pas for the mechanism. Both rows go through a
  ONE-parameter arity overload of a TWO-parameter template whose method body
  lives in an implementation section and specializes another template in
  expression position.

  THE VALUES ARE CHOSEN SO A BLANK CANNOT PASS: 3 and 7 are SizeOf of the two
  hash records, and neither is SizeOf(Pointer), SizeOf(LongInt) or 0 -- the
  answers a lost substitution or an unrecorded type would give. The second row
  spells both parameters explicitly, so the pair separates "arity overload
  resolved correctly" from "two-parameter path works at all".
  Oracled against fpc 3.2.2 -Mdelphi, which prints the same two lines.
  bug-p-a-generic-method-implementation-is-attributed-by-name-not-arity }
{$MODE DELPHI}
uses uarityoverload;
begin
  WriteLn('one-param  ', TStringOrd.Ordinal);
  WriteLn('two-param  ', TIntOrdB.Ordinal);
end.
