{ `on E: T` must catch a descendant of T declared in a LATER-compiled unit (b339).

  The on-clause used to ENUMERATE T's descendants when the handler's own unit
  lowered, so a subclass declared in a unit compiled afterwards was not in the set
  and the handler silently let it escape — "Unhandled exception" at run time, with
  nothing wrong at compile time. b322 fixed the dominant case (a ROOT `Exception`
  target matches unconditionally); this is the general one: EMyBase is NOT the
  root, so only a runtime parent-chain walk gets it right.

  except_b339_base (compiled FIRST) holds the `on E: EMyBase` handler.
  except_b339_derived (compiled LATER) declares EDerived < EMyBase, EDeep <
  EDerived — two levels, so the walk must really walk — and ENotMine < EOther,
  which must NOT be caught by the EMyBase clause. }
program test_except_open_world_descendant_b339;
{$mode objfpc}{$h+}
uses except_b339_base, except_b339_derived;

var
  fails: Integer;

procedure Check(const what, got, want: AnsiString);
begin
  if got = want then
    writeln('ok   ', what, ' -> ', got)
  else
  begin
    writeln('FAIL ', what, ' -> ', got, ' (want ', want, ')');
    fails := fails + 1;
  end;
end;

begin
  fails := 0;

  { direct descendant, declared in the later unit }
  Check('EDerived', CatchMyBase(@RaiseDerived), 'base:EDerived');

  { grandchild — the parent chain has to be walked, not just probed one level }
  Check('EDeep', CatchMyBase(@RaiseDeep), 'base:EDeep');

  { a descendant of the OTHER base: must fall through to the second handler, not
    get swept up by the EMyBase clause }
  Check('ENotMine', CatchMyBase(@RaiseNotMine), 'other:ENotMine');

  if fails = 0 then writeln('PASS') else writeln('FAILED ', fails);
end.
