{ %FAIL-style negative: `class abstract sealed`.

  The two modifiers contradict each other: `abstract` says the class must be derived
  from, `sealed` says it cannot be (tsealed3). See test_sealed_class_fail.pas. }
program test_sealed_abstract_class_fail;
{$mode objfpc}
type
  TBad = class abstract sealed
  public
  end;
begin
end.
