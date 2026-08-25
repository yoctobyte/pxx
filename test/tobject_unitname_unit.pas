{ Helper unit for test_tobject_unitname: a class DECLARED IN A UNIT, so
  UnitName has something other than the program name to answer. }
unit tobject_unitname_unit;
{$mode objfpc}{$H+}
interface
type
  TInUnit = class(TObject)
    X: Integer;
  end;
  TDerived = class(TInUnit)
    Y: Integer;
  end;
implementation
end.
