unit aoc_ovl_unit_var;
{ The sibling overloads, in a DIFFERENT unit — which is the whole point: a
  same-unit overload set always worked. See aoc_ovl_unit_fmt. }
interface
uses aoc_ovl_unit_fmt;
procedure g(const v: Variant; const spec: AnsiString); overload;
procedure k(const d: TDays); overload;
implementation
procedure g(const v: Variant; const spec: AnsiString);
begin
  WriteLn('g-var:', spec);
end;
procedure k(const d: TDays);
begin
  if dTue in d then WriteLn('k-set: dTue') else WriteLn('k-set: other');
end;
end.
