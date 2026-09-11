{ A unit cycle closed through an `implementation` uses, with ANOTHER unit named
  AFTER the cycle-closing one in the SAME clause.

  The park that makes the cycle legal keyed off a GLOBAL, CycleWaitUnit, and
  loading a later unit in the clause re-entered ParseUnitImplSection and cleared
  it. So the defect was ORDER-DEPENDENT: `uses ucyctail_a, ucyctail_t` failed
  and `uses ucyctail_t, ucyctail_a` compiled, from the same four units.

  Found on FPC's own comphook.pas, whose implementation reads
  `uses cutils, systems, globals, comptty` -- `globals` closes the cycle and
  `comptty` clears it one name later. Before the fix this was the first failure
  of five corpus units measured; fpc 3.2.2 compiles and runs both orderings.
  bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface }
program test_p_a_unit_after_the_cycle_closer_in_one_clause;

uses ucyctail_a, ucyctail_b;

var
  fails: Integer;

procedure Check(const nm: AnsiString; got, want: LongInt);
begin
  if got = want then WriteLn(nm, '=yes')
  else begin WriteLn(nm, '=NO got ', got, ' want ', want); Inc(fails); end;
end;

begin
  fails := 0;

  { The const crosses the cycle: A's interface -> B's implementation. }
  Check('const-crosses-the-cycle', TailReadsConst, 41);

  { The type crosses it too, and the body also calls into the TRAILING unit --
    so the clause's second name is exercised, not merely present. }
  Check('type-and-trailing-unit', TailReadsType(7), 8);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('UCYCTAIL OK') else WriteLn('UCYCTAIL FAIL');
end.
