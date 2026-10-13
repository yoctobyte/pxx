program esp_obj_class_vmt;
{ A class with a VMT, for the row that asserts an ESP OBJECT with no iram or
  interrupt routine puts its VMTs and class RTTI in the flash .rodata, and
  that esp_obj_class_vmt_iram.pas keeps them in writable .data. }
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
