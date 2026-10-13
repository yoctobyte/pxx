program esp_obj_class_vmt_iram;
{ esp_obj_class_vmt.pas plus one `iram;` routine. iram code runs while the
  flash cache is off, and an ISR can reach a VMT or class RTTI through an
  instance, so with any iram or interrupt routine in the program ALL class
  RTTI stays in writable .data (ObjRoAdoptRttiCandidates). The row asserts the
  section table is identical with and without --no-ro-rtti here, and that it
  differs for the iram-free fixture. }
type
  TBase = class
    function Hello: Integer; virtual;
  end;
  TDer = class(TBase)
    function Hello: Integer; override;
  end;
function TBase.Hello: Integer; begin Result := 1; end;
function TDer.Hello: Integer; begin Result := 2; end;
var
  o: TBase;
  EspCount: Integer; cvar;

procedure fast_tick; iram;
begin
  EspCount := EspCount + 1;
end;

begin
  o := TDer.Create;
  fast_tick;
  WriteLn('v=', o.Hello, ' lit');
end.
