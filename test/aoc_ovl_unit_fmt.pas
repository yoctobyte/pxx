unit aoc_ovl_unit_fmt;
{ Helper for test_array_of_const_cross_unit_overload — the unit whose `g` takes
  an `array of const`. It is deliberately the one listed LAST in the program's
  uses clause, which is the order that used to fail.
  bug-a-array-of-const-literal-does-not-match-in-a-cross-unit-overload-set }
interface
type TDay = (dMon, dTue, dWed);
     TDays = set of TDay;
procedure g(const fmt: AnsiString; const args: array of const); overload;
{ same NAME, same SLOT as the set-taking k below — the veto case }
procedure k(const args: array of const); overload;
implementation
procedure g(const fmt: AnsiString; const args: array of const);
begin
  WriteLn('g-aoc:', fmt, ' n=', Length(args));
end;
procedure k(const args: array of const);
begin
  WriteLn('k-aoc: n=', Length(args));
end;
end.
