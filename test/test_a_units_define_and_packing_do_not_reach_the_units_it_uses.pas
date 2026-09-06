program test_a_units_define_and_packing_do_not_reach_the_units_it_uses;
{ bug-p-a-units-define-leaks-into-the-units-it-uses

  FPC scopes a conditional symbol to the unit that WRITES it; only a `-d` on
  the command line is global. pxx carried one table across the whole
  compilation, so a used unit was compiled with whatever its caller happened to
  have defined -- and it does not error, it silently takes the other arm. The
  used unit is then built with a different interface, a different field set or
  different types than FPC would build, and the complaint (if any) lands
  somewhere else entirely. Compilation ORDER became semantically significant,
  which under FPC it is not.

      unit ua; {$define LEAKED} interface uses ub;
      unit ub; ... {$ifdef LEAKED} 'yes' {$else} 'no' {$endif}

      fpc 3.2.2 -Mobjfpc:  no        pxx before this fix:  yes

  THE SECOND HALF IS THE WORSE ONE and it is not in the ticket's title:
  `{$PACKRECORDS 1}` leaked exactly the same way, so a used unit's
  `record a: Byte; b: LongInt` was FIVE bytes where fpc builds eight. That is an
  ABI, in a unit that never asked for it, and no arm of any {$ifdef} is involved.
  Row 4 is that measurement.

  FOUR DIRECTIONS, because a fix that CLEARS the table instead of saving and
  restoring it passes the obvious two and fails the other two:
    down   a parent's define must not reach the child        (rows 1, 4)
    up     a child's define must not reach the parent after  (row 7)
    in     a command-line -d must reach the child            (row 2)
    self   a unit's own define must still work in that unit  (rows 3, 5, 6)

  THE ROOT SOURCE IS A DELIBERATE EXCEPTION, and this file does not test it
  because it cannot: it would be the one row where we differ from fpc on
  purpose. The MAIN program's or main unit's defines DO reach the units it
  uses, because pxx's own RTL is configured that way -- `{$undef
  PXX_MANAGED_STRING}` on line 1 of a program selects the frozen-string model
  and compiler/builtin/*.pas reads it. Cutting that turned
  test_frozen_string_reentrant.pas into `call to a runtime stub that was never
  emitted` inside builtinheap.pas, which is what a configuration define losing
  its effect looks like from the far end. That file is the positive control for
  the exception and it is already wired; do not add a second one here.

  The defect is UNIT-to-unit, where `uses` ORDER becomes semantically
  significant. The root is one source, lexically ordered, and nothing about it
  is order-dependent. Anyone wanting a genuinely cross-unit symbol has {$CLAIM}.

  Compiled with -dCLIDEF -Futest/units; every row is byte-identical to
  fpc 3.2.2 -Mobjfpc -dCLIDEF -Futest/units. }

uses udefscopeparent;

var fails: Integer;

procedure Check(const what, g, w: AnsiString);
begin
  if g <> w then
  begin
    WriteLn('FAIL ', what, ': got "', g, '" want "', w, '"');
    fails := fails + 1;
  end;
end;

procedure CheckI(const what: AnsiString; g, w: Integer);
begin
  if g <> w then
  begin
    WriteLn('FAIL ', what, ': got ', g, ' want ', w);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;

  { 1: THE ROW THIS FILE EXISTS FOR. }
  Check('1: a parent define does not reach the unit it uses',
        ChildSeesParentDefine, 'parent-define-scoped');

  { 2: ...and the boundary that stops the fix from being "clear the table".
    A -d symbol is global under FPC and must survive into every unit. }
  Check('2: a command-line -d still reaches the used unit',
        ChildSeesCommandLineDefine, 'cli-define-reaches-here');

  { 3: the used unit's OWN define still works inside it. }
  Check('3: the used unit keeps its own define',
        ChildSeesItsOwnDefine, 'own-define-works');

  { 4: the same leak in the RECORD LAYOUT, which is an ABI and not an arm. }
  CheckI('4: a parent PACKRECORDS does not reach the unit it uses',
         ChildRecordSize, 8);

  { 5: and the parent's own packing survives its own uses -- the row a
    clear-instead-of-restore fix fails. }
  CheckI('5: the parent keeps its own PACKRECORDS after the uses',
         ParentRecordSize, 5);

  { 6: the parent keeps its own define after the uses, same argument. }
  Check('6: the parent keeps its own define after the uses',
        ParentStillSeesItsOwnDefine, 'parent-keeps-its-own');

  { 7: THE REVERSE LEAK. A define written in the child must not be visible in
    the parent afterwards. }
  Check('7: a child define does not leak back up',
        ParentSeesChildDefine, 'child-define-scoped');

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('DEFSCOPE OK');
end.
