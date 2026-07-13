{ A CLASS PROPERTY reached through the class name: `TJSONData.CompressedJSON := False`
  (fcl-json).

  `class property` parsed, but was never DISPATCHED -- the class-qualified path looked for a
  method, then a class var, then gave up ("class method not found: CompressedJSON").

  Its accessors are static class methods, whose Self is the METACLASS -- so the receiver is
  simply the class reference, and the existing static-method call builder does the rest. Reads
  and writes both work; a method of the same name still wins. }
program test_class_property_b299;
type
  TD = class
  private
    class var FComp: Boolean;
    class var FLevel: Integer;
    class function GetComp: Boolean; static;
    class procedure SetComp(v: Boolean); static;
    class function GetLevel: Integer; static;
    class procedure SetLevel(v: Integer); static;
  public
    class property Compressed: Boolean read GetComp write SetComp;
    class property Level: Integer read GetLevel write SetLevel;
  end;
class function TD.GetComp: Boolean; begin Result := FComp; end;
class procedure TD.SetComp(v: Boolean); begin FComp := v; end;
class function TD.GetLevel: Integer; begin Result := FLevel; end;
class procedure TD.SetLevel(v: Integer); begin FLevel := v; end;
begin
  writeln('default : ', TD.Compressed, ' ', TD.Level);
  TD.Compressed := True;          { write through the CLASS name }
  TD.Level := 7;
  writeln('after   : ', TD.Compressed, ' ', TD.Level);
  TD.Compressed := False;
  writeln('again   : ', TD.Compressed, ' ', TD.Level);
end.
