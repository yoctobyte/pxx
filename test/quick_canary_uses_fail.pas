program quick_canary_uses_fail;
{ %FAIL-style negative: the leak itself. This program names only udeep1, whose
  own clause names udeep2, whose own clause names udeep3 — so DeepInt is three
  hops away and must not resolve. FPC 3.2.2 rejects this too.

  Named DeepInt rather than DeepFunc deliberately: routines were the FIRST
  table to get the rule and would keep this test honest even while every other
  table leaked. A const is the one that shipped broken.
  Sibling: quick_canary_uses.pas, which must compile. }
uses udeep1;
begin
  writeln(DeepInt);
end.
