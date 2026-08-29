program test_delphi_generic_cross_unit;
{ A mode-Delphi generic declared in a USED UNIT, specialized with the Delphi
  angle-bracket surface from the main program and from a third unit.

  This failed with `unknown type: TBox` — not because generics do not cross
  units (the objfpc binder spelling always worked) but because the desugar that
  rewrites `TBox<Integer>` into an alias swept only FORWARD from the template's
  own declaration. Tokens[] is one array shared by every unit and the main
  program is lexed first, so the program's uses sit BELOW the declaration and
  were never reached. The sweep now runs at the end of each `uses` clause
  instead, where everything it must rewrite is ahead of it.
  bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized

  Expected values are FPC 3.2.2's. }
{$MODE DELPHI}

uses ugdgbase, ugdgmid;

var
  ok, tot: Integer;
  b: TBox<Integer>;
  p: TPair<Integer, LongInt>;

procedure Check(const nm: string; got, want: Integer);
begin
  tot := tot + 1;
  if got = want then begin ok := ok + 1; writeln('ok   ', nm); end
  else writeln('FAIL ', nm, ' = ', got, ' want ', want);
end;

begin
  ok := 0; tot := 0;
  b := TBox<Integer>.Create;
  b.Val := 11;
  Check('one-param, cross-unit, Delphi surface', b.Val, 11);
  p := TPair<Integer, LongInt>.Create;
  p.Tag := 22;
  Check('two-param, cross-unit, Delphi surface', p.Tag, 22);
  Check('unit-to-unit use of a third unit template', MidVal, 7);
  Check('unit-to-unit, two-param', MidTag, 9);
  writeln('total ok ', ok, ' / ', tot);
end.
