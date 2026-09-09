program test_a_class_helper_on_a_class_level_method;
{$mode objfpc}{$H+}
{ Class-helper dispatch on CLASS-LEVEL members, reached through the type name.

  Until 2026-09-09 a class helper's class-level members were never applied:
  `TTest.CS` answered the class's own 1 where fpc 3.2.2 answers the helper's 2,
  the non-static `CN` the same at 10 vs 20, while INSTANCE members dispatched
  correctly (400 in both). The discriminator was the RECEIVER -- a class-level
  member reached through `TClass.Method` -- and never `static`, and never
  generics: five of these eight rows contain no generics at all.

  ONE QUESTION, FOUR COPIES, and ClassHelperRecFor's own comment said "two
  member-lookup loops" while there were four. The two INSTANCE loops asked it
  unconditionally, in front of every lookup. The metaclass loop in
  pasparser_lval.inc asked it only as a FALLBACK, when the class had no member of
  that name -- so a helper could ADD a class method and never OVERRIDE one. The
  fourth, ParseFactorCore's type-name arm, never asked at all. Both now ask, and
  ask FIRST: ClassHelperRecFor returns its input unchanged when the class's own
  member wins, so asking early is free and is the only order that answers both
  directions.

  THE LAST TWO ROWS ARE TWO DIFFERENT PARSER ARMS AND EACH NEEDS ITS OWN. Every
  expression row goes through ParseFactorCore; `TTest.Touch;` in statement
  position goes through ParseLValueAST. Measured: with only the expression arm
  fixed, seven rows were correct and `stmt-touch` still answered 1. A test made
  of expressions alone certifies half a fix.

  | row                | pxx | fpc 3.2.2 |
  | ------------------ | --: | --------: |
  | gen-TTest          |   2 |         2 |
  | gen-TTest2         |   3 |         3 |  <- WAS the known divergence; see below
  | inunit             |   2 |         2 |
  | plain-TTest        |   2 |         2 |
  | plain-TTest2       |   4 |         4 |
  | classfn-nonstatic  |  20 |        20 |
  | instance           | 400 |       400 |
  | stmt-touch         |   2 |         2 |

  `gen-TTest2` WAS A SECOND DEFECT, REVEALED AND NOT CAUSED, and it is now
  fixed. Before class-level dispatch worked at all, pxx answered 3 here and that
  MATCHED fpc -- for the wrong reason: it applied no class-level helper in any
  scope, so no exclusion rule was doing the work. The `plain-TTest2` row is what
  settled it: same class, same helper, same program, generics removed, and pxx
  answered 3 there too where fpc answers 4. The row was pinned at 3 in its own
  commit (17a0e4bd6) BEFORE dispatch was touched, precisely so the flip to 4
  would read as a defect revealed; it then read 4 for one day.

  What it revealed: fpc answers 4 for `TTest2.CS` and 3 for `specialize
  DoTest<TTest2>` -- same class, same helper, same program -- so fpc resolves a
  template body's names in the TEMPLATE's declaration context, and a helper
  declared by the SPECIALIZING program does not reach it.

  IT WAS FIXED AS A SCOPE RULE AND NOT BY NARROWING DISPATCH, which is what the
  other seven rows demanded. Two halves, both of them rules this compiler
  already had somewhere else. First, a specialized generic ROUTINE's body now
  parses as its DECLARING unit -- the rule a specialization's METHOD bodies have
  had since bug-p-a-generic-template-body-resolves-its-symbols-at-the-specialization-site,
  which a generic routine never got (measured: `DoTest_TTest` parsed at
  body-unit=-1, the PROGRAM, while the same unit's own methods carried
  body-unit=60). Second, helper lookup is visibility-aware at all --
  FindHelperForType was a flat global scan with no visibility test of any kind,
  so any helper anywhere won.

  `gen-TTest` = 2 and `gen-TTest2` = 3 are ONE RULE ON TWO INPUTS: the template
  unit's own helper still reaches the body, the specializing program's does not.
  Narrowing dispatch would have fixed the second and broken the first.

  bug-p-a-generic-routine-body-does-not-see-its-own-units-class-helper
  bug-p-a-generic-template-body-is-resolved-in-the-specializers-scope-not-its-own }
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
  { STATEMENT POSITION, and it is a SECOND parser arm -- the six rows above are
    all expressions and none of them can see it. `TTest.Touch;` goes through
    ParseLValueAST's metaclass lookup; `TTest.CS` inside a WriteLn goes through
    ParseFactorCore's type-name arm. Measured: with only the expression arm fixed
    this row still answered 1 while every other row was already correct, which is
    exactly the one-armed double case normalise-dont-special-case names. }
  TTest.Touch;
  WriteLn('stmt-touch        = ', Trace);
  o.Free;
end.
