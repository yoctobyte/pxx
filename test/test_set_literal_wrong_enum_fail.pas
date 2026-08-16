{ %FAIL-style negative: a set literal element that is not a member of the
  target set's element enum. `[cGreen]` used to compile and answer dTue --
  two unrelated enums were freely interchangeable inside a set literal, so a
  refactor swapping one for the other could not be caught anywhere a set
  literal was involved. FPC: "Incompatible types ... Array of TColor, expected
  TDays". bug-p-set-literal-elements-are-not-type-checked }
{$mode objfpc}
program setlitwrongenum;
type
  TDay   = (dMon, dTue, dWed);
  TDays  = set of TDay;
  TColor = (cRed, cGreen, cBlue);
procedure TakesSet(d: TDays);
begin
  if dTue in d then WriteLn('dTue is in the set') else WriteLn('it is not');
end;
begin
  TakesSet([cGreen]);
end.
