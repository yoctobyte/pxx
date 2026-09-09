unit uclshelperdispatch;
{$mode objfpc}{$H+}
{ Support unit for test_a_class_helper_on_a_class_level_method.pas. The class,
  its helper and the generic template all live HERE, above and beside each
  other, so that no row in the test depends on the specializing program's scope
  -- which is the axis the two questions in this file are separated along.
  See the test for what each row means.
  bug-p-a-generic-routine-body-does-not-see-its-own-units-class-helper }
interface
var
  { written by Touch, because a class PROCEDURE has no result to compare and the
    statement position is the only way to reach one. See the test's stmt row. }
  Trace: LongInt;

type
  TTest = class
    class function CS: LongInt; static;   { class function, static }
    class function CN: LongInt;           { class function, NON-static }
    class procedure Touch;                { STATEMENT position -- a different parser arm }
    function Inst: LongInt;               { ordinary instance method }
  end;

  TTestHelper = class helper for TTest
    class function CS: LongInt; static;
    class function CN: LongInt;
    class procedure Touch;
    function Inst: LongInt;
  end;

generic function DoTest<T: TTest>: LongInt;
function InUnitPlain: LongInt;

implementation

class function TTest.CS: LongInt; begin Result := 1; end;
class function TTest.CN: LongInt; begin Result := 10; end;
class procedure TTest.Touch; begin Trace := 1; end;
function TTest.Inst: LongInt; begin Result := 200; end;

class function TTestHelper.CS: LongInt; begin Result := 2; end;
class function TTestHelper.CN: LongInt; begin Result := 20; end;
class procedure TTestHelper.Touch; begin Trace := 2; end;
function TTestHelper.Inst: LongInt; begin Result := 400; end;

generic function DoTest<T>: LongInt; begin Result := T.CS; end;

{ The same call the template makes, hand-written, in the same unit. It is the
  row that says the substituted body behaves like ordinary code -- without it a
  class-helper dispatch defect is indistinguishable from a generics defect. }
function InUnitPlain: LongInt; begin Result := TTest.CS; end;

end.
