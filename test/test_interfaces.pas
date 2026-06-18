program TestInterfaces;
{$mode objfpc}
type
  IShape = interface
    function Area: Integer;
    function Scale(factor: Integer): Integer;
    procedure SetSize(aw, ah: Integer);
  end;
  TRect = class(IShape)
    w, h: Integer;
    function Area: Integer;
    function Scale(factor: Integer): Integer;
    procedure SetSize(aw, ah: Integer);
  end;

function TRect.Area: Integer; begin Result := Self.w * Self.h; end;
function TRect.Scale(factor: Integer): Integer; begin Result := Self.w * Self.h * factor; end;
procedure TRect.SetSize(aw, ah: Integer); begin Self.w := aw; Self.h := ah; end;

var
  s: IShape;
  r: TRect;
begin
  r := TRect.Create;
  r.w := 4; r.h := 5;
  s := r;
  writeln('area=', s.Area);          { 20 }
  writeln('scaled=', s.Scale(3));    { 60 }
  s.SetSize(6, 7);                    { mutate through the interface }
  writeln('area2=', s.Area);          { 42 }
  writeln('direct=', r.Area);         { 42 — same instance }
end.
