{ %FAIL-style negative: a bare ordinal in a set literal bound to `set of TEnum`.
  `['a', 1]` used to compile and answer dTue; `[99]` -- out of the enum's range
  -- silently produced the EMPTY set with no diagnostic at any level. Both are
  the same missing check: an element must be a member of the target enum.
  bug-p-set-literal-elements-are-not-type-checked }
{$mode objfpc}
program setlitplain;
type
  TDay  = (dMon, dTue, dWed);
  TDays = set of TDay;
procedure TakesSet(d: TDays);
begin
  if dTue in d then WriteLn('dTue is in the set') else WriteLn('it is not');
end;
begin
  TakesSet(['a', 1]);
end.
