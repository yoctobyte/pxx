program TestAbstractOut;

{ Test 1: abstract methods — dispatcher calls override, not abstract stub }
type
  TShape = class
    constructor Create;
    function Area: Integer; virtual; abstract;
    function Describe: Integer; virtual;
  end;

  TSquare = class(TShape)
    Side: Integer;
    constructor Create;
    function Area: Integer; override;
  end;

  TCircle = class(TShape)
    Radius: Integer;
    constructor Create;
    function Area: Integer; override;
  end;

constructor TShape.Create;
begin
end;

function TShape.Describe: Integer;
begin
  Result := Area * 2;
end;

constructor TSquare.Create;
begin
  Side := 4;
end;

function TSquare.Area: Integer;
begin
  Result := Side * Side;
end;

constructor TCircle.Create;
begin
  Radius := 3;
end;

function TCircle.Area: Integer;
begin
  Result := Radius * Radius;   { simplified — no float }
end;

{ Test 2: out parameters }
procedure GetValues(out a: Integer; out b: Integer);
begin
  a := 42;
  b := 99;
end;

procedure Swap(var x: Integer; out y: Integer; z: Integer);
begin
  y := x;
  x := z;
end;

var
  sq: TSquare;
  ci: TCircle;
  s: TShape;
  p, q, r: Integer;
begin
  sq := TSquare.Create;
  ci := TCircle.Create;

  writeln(sq.Area);          { 16 }
  writeln(ci.Area);          { 9 }

  { polymorphic dispatch through base pointer }
  s := sq;
  writeln(s.Area);           { 16 }
  writeln(s.Describe);       { 32 }
  s := ci;
  writeln(s.Describe);       { 18 }

  { out parameters }
  GetValues(p, q);
  writeln(p);                { 42 }
  writeln(q);                { 99 }

  r := 7;
  Swap(r, p, 100);
  writeln(r);                { 100 }
  writeln(p);                { 7 }
end.
