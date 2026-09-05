{ The corpus shape, in a unit: a method-pointer type between a mode-Delphi
  generic template and a use of it inside a routine body in the IMPLEMENTATION.
  Helper for test_delphi_generic_of_object_anchor.pas -- see that file. }
unit dgen_of_object_unit;
{$MODE DELPHI}
interface
type
  UArg = class end;
  UBox<T: class> = class
    class function Who: Integer;
  end;
  UCb = function(x: Integer): Integer of object;   { the derailer }
  UUser = class
    class function GetIt: Integer;
  end;
implementation

{ A bare `function` body: its own `end` decrements a depth nothing incremented,
  which is how the miscount reaches 0 again inside the implementation. }
function UDrain: Integer;
begin
  Result := 0;
end;

class function UBox<T>.Who: Integer;
begin
  Result := 7;
end;

class function UUser.GetIt: Integer;
var b: UBox<UArg>;
begin
  b := nil;
  if b = nil then Result := UBox<UArg>.Who else Result := UDrain;
end;

end.
