program esp_obj_class_vmt;
{ A class with a VMT, for the row that asserts an ESP OBJECT keeps its VMTs and
  class RTTI writable (.data), not in the flash .rodata -- see RoRttiWanted. }
type
  TBase = class
    function Hello: Integer; virtual;
  end;
  TDer = class(TBase)
    function Hello: Integer; override;
  end;
function TBase.Hello: Integer; begin Result := 1; end;
function TDer.Hello: Integer; begin Result := 2; end;
var o: TBase;
begin
  o := TDer.Create;
  WriteLn('v=', o.Hello, ' lit');
end.
