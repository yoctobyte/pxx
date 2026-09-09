{ THE POPULATION IS "A PROGRAM WITH NO USES CLAUSE", and that is the whole
  point of the file: every other test of these members reaches them from a
  program that already pulled the builtin unit for some other reason.

  `x.UnitName` and `x.ClassInfo` lower to __pxxUnitName / __pxxClassInfo, which
  live in the builtin unit. Nothing in the token stream announces them -- both
  are written as a bare name with no arguments and no '(' -- so a token
  PRE-SCAN (pasparser_prog.inc) has to recognise the spelling and pull the unit
  before the parse. When the name is missing from that list, GenMakeClassRefOp
  finds no proc, returns -1, and the caller falls through to ordinary member
  lookup: `class method not found (UnitName)`, which names the MEMBER when what
  is actually absent is the UNIT.

  MEASURED, not theoretical: `unitname` landed 2026-08-25 without its trigger
  and this shape was refused from that day until 2026-09-09. It survived
  because test_tobject_unitname.pas `uses` a helper unit and every other caller
  in the tree writes ClassName in the same program -- the trigger was always
  pulled by a neighbour. Removing only the `unitname` term and rebuilding
  reproduces the refusal exactly, which is this file's positive control.

  So: no uses clause, no ClassName, no `is`, nothing else on the trigger list.
  Adding any of those to this file destroys it as a guard while leaving every
  row green. Expected output is fpc 3.2.2's own (-Mobjfpc -O1).
  feature-a-classinfo-returns-the-typinfo-header }
{$mode objfpc}{$H+}
program test_classref_member_needs_no_uses;
type
  TFoo = class(TObject)
    X: Integer;
  end;
var
  f: TFoo;
begin
  WriteLn(TFoo.UnitName);
  WriteLn(TFoo.ClassInfo <> nil);
  f := TFoo.Create;
  WriteLn(f.UnitName);
  WriteLn(f.ClassInfo = TFoo.ClassInfo);
end.
