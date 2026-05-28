program test_ir_virtual_call;

type
  TBase = class
    constructor Create;
    function Kind: Integer; virtual;
  end;

  TDerived = class(TBase)
    constructor Create;
    function Kind: Integer; override;
  end;

constructor TBase.Create;
begin
end;

function TBase.Kind: Integer;
begin
  Result := 1;
end;

constructor TDerived.Create;
begin
end;

function TDerived.Kind: Integer;
begin
  Result := 2;
end;

var
  b: TBase;
  d: TDerived;
  r: TBase;
begin
  b := TBase.Create;
  d := TDerived.Create;
  r := b;

  writeln(b.Kind);
  writeln(d.Kind);
  writeln(r.Kind);

  r := d;
  writeln(r.Kind);
end.
