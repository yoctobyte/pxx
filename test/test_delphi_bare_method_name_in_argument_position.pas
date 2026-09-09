program mref; {$mode delphi}
type
  TOnHash = function(const v: LongInt): LongInt of object;
  TBase = class
    function HashIt(const v: LongInt): LongInt;
    function Virt(const v: LongInt): LongInt; virtual;
    function Paramless: LongInt;
    function Defaulted(const v: LongInt = 7): LongInt;
    procedure Take(const h: TOnHash);
    procedure TakeInt(const n: LongInt);
    procedure Go;
    procedure GoParamless;
    procedure GoDefaulted;
  end;
  TDer = class(TBase)
    function Virt(const v: LongInt): LongInt; override;
    procedure GoVirt;
  end;
function TBase.HashIt(const v: LongInt): LongInt; begin Result := v + 1; end;
function TBase.Virt(const v: LongInt): LongInt; begin Result := 100 + v; end;
function TBase.Paramless: LongInt; begin Result := 5; end;
function TBase.Defaulted(const v: LongInt): LongInt; begin Result := v * 10; end;
procedure TBase.Take(const h: TOnHash); begin WriteLn('took ', h(41)); end;
procedure TBase.TakeInt(const n: LongInt); begin WriteLn('int ', n); end;
procedure TBase.Go; begin Take(HashIt); end;
procedure TBase.GoParamless; begin TakeInt(Paramless); end;
procedure TBase.GoDefaulted; begin TakeInt(Defaulted); end;
function TDer.Virt(const v: LongInt): LongInt; begin Result := 200 + v; end;
procedure TDer.GoVirt; begin Take(Virt); end;
var b: TBase; d: TDer;
begin
  b := TBase.Create; d := TDer.Create;
  b.Go;                  { bare method name -> referenced }
  d.GoVirt;              { virtual: must bind the OVERRIDE }
  b.GoParamless;         { BARE paramless function -> CALLED, not referenced }
  b.GoDefaulted;         { BARE all-defaulted      -> CALLED, not referenced }
end.
