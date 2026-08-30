{ --warn-ignored-directives: a routine directive that is accepted and then
  dropped should say so, and say WHY. Silent without the flag — these are all
  legal FPC source. `Ok` is the control: it IS inlinable at -O2, so it must NOT
  warn. feature-pascal-warn-on-unfulfillable-directive

  COUNT IS 5, NOT 6, AND `cdecl` IS THE SECOND CONTROL. It warned until
  feature-cdecl-bodied-sysv-prologue gave a bodied `cdecl` proc a genuine SysV
  prologue on x86-64, at which point the warning's own claim -- "the convention
  is not selectable per routine" -- became false on this target and the
  compiler correctly stopped making it. The other five targets keep it, so a
  cross-target run of this file would count 6; the suite runs it natively.
  A directive LEAVING this population is the expected shape of progress here,
  so a future drop to 4 is a stale expectation before it is a regression --
  check pasparser_proc.inc for a narrowing comment before filing one. }
program test_warn_ignored_directives;
procedure P; cdecl; begin end;
procedure Q; register; begin end;
procedure R; iram; begin end;
procedure S1; stackful; begin end;
function Big(a,b,c,d,e,f,g: Integer): Integer; inline; begin Big := a; end;
procedure NotFn; inline; begin end;
function Ok(a: Integer): Integer; inline; begin Ok := a; end;
begin
  P; Q; R; S1; NotFn;
  writeln(Big(1,2,3,4,5,6,7));
  writeln(Ok(1));
end.
