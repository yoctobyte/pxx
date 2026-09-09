program test_a_class_helper_on_a_class_level_method;
{$mode objfpc}{$H+}
{ THIS FILE PINS A DEFECT. Five of its seven rows record what pxx answers TODAY
  and today's answer is WRONG; the expected file is a snapshot, not a
  specification. Read the table below before changing it.

  A class helper's CLASS-LEVEL members are never applied: `TTest.CS` answers the
  class's own 1 where fpc 3.2.2 answers the helper's 2, and the same for the
  non-static `CN` (10 vs 20). INSTANCE members dispatch correctly (400 in both).
  So the discriminator is the RECEIVER -- a class-level member reached through
  `TClass.Method` -- and not `static`, and not generics.

  WHY IT IS PINNED BEFORE THE FIX RATHER THAN WITH IT. One row, `gen-TTest2`,
  currently agrees with fpc at 3, and it agrees FOR THE WRONG REASON: pxx applies
  no class-level helper in any scope, so there is no exclusion rule doing the
  work. The row beneath it settles that -- `plain-TTest2` is the same class, the
  same helper and the same program with the generics removed, and pxx answers 3
  there too where fpc answers 4. A dispatch fix will therefore flip `gen-TTest2`
  to 4 with nothing to stop it. Committed here first so that flip reads as a
  defect REVEALED and not one caused.

  | row                | pxx now | fpc 3.2.2 | what it means                     |
  | ------------------ | ------: | --------: | --------------------------------- |
  | gen-TTest          |       1 |         2 | WRONG -- helper in template's own unit |
  | gen-TTest2         |       3 |         3 | agrees, FOR THE WRONG REASON      |
  | inunit             |       1 |         2 | WRONG -- no generics in this row  |
  | plain-TTest        |       1 |         2 | WRONG -- no generics, no unit boundary |
  | plain-TTest2       |       3 |         4 | WRONG -- and this is what makes gen-TTest2 accidental |
  | classfn-nonstatic  |      10 |        20 | WRONG -- so `static` is not the discriminator |
  | instance           |     400 |       400 | CORRECT -- instance helper members do dispatch |

  WHEN THE DISPATCH FIX LANDS, five rows become correct (1->2, 1->2, 1->2, 3->4,
  10->20) and `gen-TTest2` becomes WRONG at 4 against fpc's 3. That is not a
  regression to undo. fpc gives 4 for `plain-TTest2` and 3 for `gen-TTest2` on
  the same class, helper and program, which is the actual evidence that fpc binds
  a template body in the TEMPLATE's declaration context -- a real second defect
  that is not measurable until helpers are applied at all. Split it out then.

  bug-p-a-generic-routine-body-does-not-see-its-own-units-class-helper }
uses uclshelperdispatch;
type
  { TTest2 declares its OWN CS (3) as well as having a helper (4). Both must be
    present: with only the helper, "3" could mean the inherited TTest.CS and the
    row would not separate "no helper applied" from "wrong class member". }
  TTest2 = class(TTest)
    class function CS: LongInt; static;
  end;
  TTest2Helper = class helper for TTest2
    class function CS: LongInt; static;
  end;
class function TTest2.CS: LongInt; begin Result := 3; end;
class function TTest2Helper.CS: LongInt; begin Result := 4; end;
var o: TTest;
begin
  WriteLn('gen-TTest         = ', specialize DoTest<TTest>);
  WriteLn('gen-TTest2        = ', specialize DoTest<TTest2>);
  WriteLn('inunit            = ', InUnitPlain);
  WriteLn('plain-TTest       = ', TTest.CS);
  WriteLn('plain-TTest2      = ', TTest2.CS);
  WriteLn('classfn-nonstatic = ', TTest.CN);
  o := TTest.Create;
  WriteLn('instance          = ', o.Inst);
  o.Free;
end.
