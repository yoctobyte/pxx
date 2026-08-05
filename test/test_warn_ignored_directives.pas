{ --warn-ignored-directives: a routine directive that is accepted and then
  dropped should say so, and say WHY. Silent without the flag — these are all
  legal FPC source. `Ok` is the control: it IS inlinable at -O2, so it must NOT
  warn. feature-pascal-warn-on-unfulfillable-directive }
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
