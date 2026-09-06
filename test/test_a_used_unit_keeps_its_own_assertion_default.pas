program test_a_used_unit_keeps_its_own_assertion_default;
{ bug-p-a-units-define-leaks-into-the-units-it-uses -- the row that cannot be
  an fpc differential, split out rather than left uncovered.

  udefscopeparent sets {$ASSERTIONS OFF} and uses udefscopechild, which sets
  nothing. Under a correct pxx the child keeps pxx's OWN default, which is
  assertions ON (deliberately not FPC's -- see AssertionsVal in defs.inc), so
  its Assert fires. Under the leak the parent's OFF reached it and the Assert
  was silent.

  WHY IT IS NOT IN THE DIFFERENTIAL FILE: fpc defaults assertions OFF, so a
  correct fpc and the pxx LEAK print the same string, and a row that cannot
  distinguish the defect from the oracle is not a differential row -- it is two
  answers that happen to collide. Kept as a pxx-only assertion, which is what it
  actually is. The other four members of this leak family (define, PACKRECORDS,
  {$R+}, {$Q+}) are all genuinely differential and live in
  test_a_units_define_and_packing_do_not_reach_the_units_it_uses.pas. }

uses udefscopeparent;

begin
  if ChildAssertions <> 'assert-fires' then
  begin
    WriteLn('FAIL: a used unit inherited the parent''s {$ASSERTIONS OFF}: got "',
            ChildAssertions, '" want "assert-fires"');
    WriteLn('fails=1');
  end
  else
    WriteLn('fails=0');
  if ChildAssertions = 'assert-fires' then WriteLn('ASSERTDEFAULT OK');
end.
