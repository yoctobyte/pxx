program test_inherited;

type
  TBase = class
    FValue: Integer;
    constructor Create(v: Integer);
    procedure Speak; virtual;
    procedure Touch; virtual;
    function Calc: Integer; virtual;
  end;

  TChild = class(TBase)
    constructor Create(v: Integer);
    procedure Speak; override;
    procedure Touch; override;
    function Calc: Integer; override;
  end;

constructor TBase.Create(v: Integer);
begin
  FValue := v;
end;

procedure TBase.Speak;
begin
  writeln('base');
end;

procedure TBase.Touch;
begin
  writeln('touch');
end;

function TBase.Calc: Integer;
begin
  Result := FValue * 2;
end;

constructor TChild.Create(v: Integer);
begin
  inherited Create(v);
end;

procedure TChild.Speak;
begin
  inherited Speak;
  writeln('child');
end;

procedure TChild.Touch;
begin
  inherited;
  writeln('child touch');
end;

function TChild.Calc: Integer;
begin
  Result := inherited Calc + 1;
end;

var
  c: TChild;

begin
  c := TChild.Create(42);
  writeln(c.FValue);
  c.Speak;
  writeln(c.Calc);
  c.Touch;
end.
