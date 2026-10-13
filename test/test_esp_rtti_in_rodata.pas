program test_esp_rtti_in_rodata;
{ CLASS RTTI IN .rodata ON AN ESP OBJECT WITH NO iram; ROUTINE (2026-10-13).
  Headers, VMTs and the method/field/param arrays move from .data (SRAM) to
  .rodata (flash, DROM) when nothing can read them with the flash cache off.
  Everything here reads that RTTI at run time -- virtual dispatch, ClassName,
  ClassParent, is/as, an interface's refcount through its IMT -- so a wrong
  section, addend or self-relative word shows as a wrong line or a fault.
  Compared with the x86-64 oracle, where the same arrays are now read-only
  too, so a run-time WRITE into them faults there. }
type
  TShape = class
    FName: AnsiString;
    constructor Create(const n: AnsiString);
    function Area: Integer; virtual;
    function Describe: AnsiString; virtual;
  end;
  TRect = class(TShape)
    W, H: Integer;
    constructor Create(aw, ah: Integer);
    function Area: Integer; override;
  end;
  TSquare = class(TRect)
    constructor Create(s: Integer);
    function Describe: AnsiString; override;
  end;
  ICounter = interface
    function Next: Integer;
  end;
  TCounter = class(TInterfacedObject, ICounter)
    N: Integer;
    function Next: Integer;
  end;

constructor TShape.Create(const n: AnsiString);
begin
  FName := n;
end;
function TShape.Area: Integer;
begin
  Result := 0;
end;
function TShape.Describe: AnsiString;
var s: AnsiString;
begin
  Str(Area, s);
  Result := FName + ' area ' + s;
end;
constructor TRect.Create(aw, ah: Integer);
begin
  inherited Create('rect');
  W := aw; H := ah;
end;
function TRect.Area: Integer;
begin
  Result := W * H;
end;
constructor TSquare.Create(s: Integer);
begin
  inherited Create(s, s);
  FName := 'square';
end;
function TSquare.Describe: AnsiString;
begin
  Result := 'sq:' + inherited Describe;
end;
function TCounter.Next: Integer;
begin
  Inc(N);
  Result := N;
end;

var
  shapes: array[0..2] of TShape;
  i, total: Integer;
  c: ICounter;
begin
  shapes[0] := TShape.Create('blob');
  shapes[1] := TRect.Create(3, 4);
  shapes[2] := TSquare.Create(5);
  total := 0;
  for i := 0 to 2 do
  begin
    writeln(shapes[i].ClassName, ' ', shapes[i].Describe);
    total := total + shapes[i].Area;
    if shapes[i] is TRect then writeln('  is TRect, W=', TRect(shapes[i]).W);
    if shapes[i].ClassParent <> nil then writeln('  parent ', shapes[i].ClassParent.ClassName);
  end;
  writeln('total ', total);
  c := TCounter.Create;
  c.Next; c.Next;
  writeln('counter ', c.Next);
  c := nil;
  for i := 0 to 2 do shapes[i].Free;
  writeln('done');
end.
